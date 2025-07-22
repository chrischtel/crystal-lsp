require "./ext/**"
require "./base/**"
require "./notifications/**"
require "./requests/**"
require "./response_message"
require "./tools"
require "./log"
require "./platform"
require "./io_utils"

# A Language Server Protocol implementation optimized for Windows compatibility.
#
# This server provides robust I/O handling, proper URI/path management,
# and platform-specific optimizations for Windows environments.
# Actual language-specific actions are delegated to an external controller class.
class LSP::Server
  # True if the server is shutting down.
  @shutdown = false

  # True if the server has been initialized.
  @initialized = false

  # Input from which messages are received.
  getter input : ::IO
  # Output to which the messages are sent.
  getter output : ::IO
  # The broadcasted server capabilities.
  getter server_capabilities : LSP::ServerCapabilities
  # The LSP client capabilities.
  getter! client_capabilities : LSP::ClientCapabilities
  # A list of requests that were sent to clients to keep track of the ID and kind.
  getter requests_sent : Hash(RequestMessage::RequestId, LSP::Message) = {} of RequestMessage::RequestId => LSP::Message
  # Incremental request ID counter.
  @max_request_id = Atomic(Int64).new(0)
  # Lock to prevent message interleaving.
  @out_lock = Mutex.new(:reentrant)
  # This server thread, that should not get blocked by all means.
  getter thread : Thread
  # Platform-specific settings
  @platform_info : Hash(String, String)

  # Default server capabilities optimized for Windows.
  DEFAULT_SERVER_CAPABILITIES = LSP::ServerCapabilities.new(
    text_document_sync: LSP::TextDocumentSyncOptions.new(
      open_close: true,
      change: LSP::TextDocumentSyncKind::Incremental
    ),
    workspace: LSP::WorkspaceValue.new(
      workspace_folders: LSP::WorkspaceFoldersServerCapabilities.new(
        supported: true,
        change_notifications: true
      )
    )
  )

  # Initialize a new LSP Server with Windows-optimized settings.
  def initialize(@input = STDIN, @output = STDOUT, @server_capabilities = DEFAULT_SERVER_CAPABILITIES)
    @thread = Thread.current
    @platform_info = gather_platform_info

    # Setup logging with Windows compatibility
    setup_logging

    Log.info { "Initializing LSP Server on #{@platform_info["os"]} (#{@platform_info["arch"]})" }
    Log.debug { "Platform info: #{@platform_info}" }
  end

  # Gather platform information for debugging and compatibility
  private def gather_platform_info : Hash(String, String)
    info = Hash(String, String).new
    info["os"] = LSP::Platform.windows? ? "Windows" : "Unix"
    info["arch"] = {% if flag?(:x86_64) %}"x86_64"{% elsif flag?(:i386) %}"i386"{% elsif flag?(:aarch64) %}"aarch64"{% else %}"unknown"{% end %}
    info["crystal_version"] = Crystal::VERSION
    info["line_ending"] = LSP::Platform.line_ending.inspect
    info["path_separator"] = LSP::Platform.windows? ? "\\\\" : "/"
    info
  end

  # Setup logging with Windows-compatible backend
  private def setup_logging
    LSP::Log.backend = LogBackend.new(self)

    # Enable debug logging in development
    {% unless flag?(:release) %}
      ::Log.setup(:debug, LSP::Log.backend.not_nil!)
    {% end %}

    # Optional: Log to file for debugging (commented out by default)
    # log_file_path = LSP::Platform.windows? ? ".\\lsp_logs.txt" : "./lsp_logs.txt"
    # Log.backend = ::Log::IOBackend.new(File.new(log_file_path, mode: "a+"))
  end

  # Send a message to the client with Windows-compatible I/O.
  def send(message : LSP::Message, *, do_not_log = false)
    if message.is_a? LSP::RequestMessage
      @requests_sent[message.id] = message
    end

    unless do_not_log
      Log.debug { "[Server -> Client] #{message.class.name}" }
      Log.trace { "[Server -> Client] #{message.to_json}" }
    end

    @out_lock.synchronize do
      begin
        LSP::IO.write_message(@output, message)
      rescue ex : ::IO::Error
        Log.error(exception: ex) { "Failed to send message to client" }
        raise ex
      end
    end
  end

  # Send an array of messages to the client.
  def send(messages : Array, *, do_not_log = false)
    messages.each do |message|
      send(message: message, do_not_log: do_not_log)
    end
  end

  # Reply to a request initiated by the client with the provided result.
  def reply(request : LSP::RequestMessage, *, result : T, do_not_log = false) forall T
    response_message = LSP::ResponseMessage(T).new(
      id: request.id || @max_request_id.add(1),
      result: result
    )
    send(message: response_message, do_not_log: do_not_log)
  end

  # Reply to a request initiated by the client with an error.
  def reply(request : LSP::RequestMessage, *, exception, do_not_log = false)
    error = case exception
            when LSP::Exception
              LSP::ResponseError.new(exception)
            when Exception
              LSP::ResponseError.new(
                code: LSP::ErrorCodes::InternalError.value,
                message: exception.message || "Internal error",
                data: exception.class.name
              )
            else
              LSP::ResponseError.new(
                code: LSP::ErrorCodes::InternalError.value,
                message: exception.to_s
              )
            end

    response_message = LSP::ResponseMessage(Nil).new(
      id: request.id,
      error: error
    )
    send(message: response_message, do_not_log: do_not_log)
  end

  # Read a client message and deserialize it with Windows compatibility.
  protected def self.read(io : ::IO) : LSP::Message
    LSP::IO.read_message(io)
  end

  # Enhanced handshake with better error handling and Windows compatibility.
  private def handshake(controller)
    Log.debug { "Starting LSP handshake..." }

    loop do
      begin
        initialize_message = self.class.read(@input)

        if initialize_message.is_a? LSP::InitializeRequest
          Log.debug { "Received initialize request from client" }
          @client_capabilities = initialize_message.params.capabilities

          # Call controller initialization if supported
          init_result = if controller.responds_to? :on_init
                         controller.on_init(initialize_message.params)
                       else
                         nil
                       end

          # Build initialization result with Windows-specific information
          result = init_result || LSP::InitializeResult.new(
            capabilities: @server_capabilities,
            server_info: {
              name: "Crystal LSP Server",
              version: LSP::VERSION
            }
          )

          reply(initialize_message, result: result)
          @initialized = true
          Log.info { "LSP handshake completed successfully" }
          break

        elsif initialize_message.is_a? LSP::RequestMessage
          Log.warn { "Received #{initialize_message.method} before initialize request" }
          reply(initialize_message, exception: LSP::Exception.new(
            code: :server_not_initialized,
            message: "Server not initialized. Expected 'initialize' request but received '#{initialize_message.method}'."
          ))
        else
          Log.warn { "Received unexpected message type during handshake: #{initialize_message.class}" }
        end

      rescue ex : ::IO::Error
        Log.error(exception: ex) { "I/O error during handshake" }
        exit(1)
      rescue ex : LSP::Exception
        Log.error(exception: ex) { "LSP error during handshake" }
        # Continue trying to handshake
      rescue ex
        Log.error(exception: ex) { "Unexpected error during handshake" }
        # Continue trying to handshake
      end
    end
  end

  # Enhanced exception handling with Windows-specific error reporting.
  private def on_exception(message, exception)
    Log.error(exception: exception) { "Error processing message: #{exception.message}" }

    # Enhanced error context for Windows debugging
    if LSP::Platform.windows?
      Log.debug { "Windows-specific error context: PID=#{Process.pid}" }
    end

    if message.is_a? LSP::RequestMessage
      reply(request: message, exception: exception)
    end
  end

  # Enhanced main I/O loop with Windows compatibility and robust error handling.
  private def server_loop(controller)
    Log.debug { "Starting main server loop..." }
    message_count = 0

    loop do
      begin
        # Read incoming message
        message = self.class.read(@input)
        message_count += 1

        Log.trace { "Processing message ##{message_count}: #{message.class.name}" }

        # Handle special control messages
        if message.is_a? LSP::ExitNotification
          Log.info { "Received exit notification, shutting down server" }
          cleanup_and_exit(controller)
        end

        # Check if server is shutting down
        if @shutdown
          raise LSP::Exception.new(
            code: :invalid_request,
            message: "Server is shutting down and cannot process new requests."
          )
        end

        # Handle shutdown request
        if message.is_a? LSP::ShutdownRequest
          Log.info { "Received shutdown request" }
          @shutdown = true
          reply(request: message, result: nil)
          next
        end

        # Ensure server is initialized before processing other messages
        unless @initialized
          if message.is_a? LSP::RequestMessage
            reply(message, exception: LSP::Exception.new(
              code: :server_not_initialized,
              message: "Server has not been initialized yet."
            ))
          end
          next
        end

        # Delegate message handling to controller
        delegate(controller, message)

      rescue ex : ::IO::EOFError
        Log.info { "Client disconnected (EOF)" }
        break
      rescue ex : ::IO::Error
        Log.error(exception: ex) { "I/O error in server loop" }
        # On Windows, some I/O errors might be recoverable
        if LSP::Platform.windows? && recoverable_io_error?(ex)
          Log.warn { "Attempting to recover from I/O error..." }
          sleep(100.milliseconds)
          next
        else
          break
        end
      rescue ex : LSP::Exception
        on_exception(message, ex)
      rescue ex
        Log.error(exception: ex) { "Unexpected error in server loop" }
        on_exception(message, ex)
      end
    end

    Log.info { "Server loop ended after processing #{message_count} messages" }
  end

  # Check if an I/O error might be recoverable on Windows
  private def recoverable_io_error?(error : ::IO::Error) : Bool
    return false unless LSP::Platform.windows?

    message = error.message
    return false unless message

    # Some Windows I/O errors that might be temporary
    message.includes?("temporarily unavailable") ||
    message.includes?("would block") ||
    message.includes?("interrupted")
  end

  # Clean shutdown and exit
  private def cleanup_and_exit(controller)
    Log.debug { "Performing cleanup before exit..." }

    begin
      if controller.responds_to? :on_shutdown
        controller.on_shutdown
      end
    rescue ex
      Log.warn(exception: ex) { "Error during controller shutdown" }
    end

    # Close I/O streams safely
    LSP::IO.safe_close(@input) unless @input.same?(STDIN)
    LSP::IO.safe_close(@output) unless @output.same?(STDOUT)

    exit(0)
  end

  # Enhanced message delegation with better error handling and async processing.
  private def delegate(controller, message : LSP::RequestMessage)
    if controller.responds_to? :on_request
      spawn(name: "request-#{message.id}-#{message.method}") do
        begin
          result = controller.on_request(message)
          reply(request: message, result: result)
        rescue ex
          on_exception(message, ex)
        end
      end
    else
      # Default response for unhandled requests
      reply(request: message, result: nil)
    end
  end

  private def delegate(controller, message : LSP::NotificationMessage)
    if controller.responds_to? :on_notification
      spawn(name: "notification-#{message.method}") do
        begin
          controller.on_notification(message)
        rescue ex
          on_exception(message, ex)
        end
      end
    else
      Log.debug { "Ignoring unhandled notification: #{message.method}" }
    end
  end

  private def delegate(controller, message : LSP::ResponseMessage)
    if controller.responds_to? :on_response
      spawn(name: "response-#{message.id}") do
        begin
          original_message = @requests_sent.delete(message.id)
          controller.on_response(message, original_message.try(&.as(RequestMessage)))
        rescue ex
          on_exception(message, ex)
        end
      end
    else
      # Remove from tracking even if not handled
      @requests_sent.delete(message.id)
      Log.debug { "Ignoring unhandled response: #{message.id}" }
    end
  end

  # Enhanced server startup with Windows compatibility.
  def start(controller)
    Log.info { "Starting LSP server..." }
    Log.debug { "Platform: #{@platform_info["os"]} #{@platform_info["arch"]}" }

    # Set server reference on controller if it supports it
    if controller.responds_to? :server=
      controller.server = self
    end

    # Validate I/O streams
    validate_io_streams

    # Perform handshake
    handshake(controller)

    # Give controller a chance to perform initialization
    if controller.responds_to? :when_ready
      begin
        Log.debug { "Calling controller when_ready callback..." }
        controller.when_ready
      rescue ex
        Log.warn(exception: ex) { "Error during controller initialization" }
      end
    end

    Log.info { "LSP server is ready and listening for messages" }

    # Start the main server loop
    server_loop(controller)
  end

  # Validate that I/O streams are properly configured
  private def validate_io_streams
    unless LSP::IO.connected?(@input)
      raise "Input stream is not connected or readable"
    end

    # Don't check output stream connectivity as it might not be immediately testable
    Log.debug { "I/O streams validated successfully" }
  end

  # Get server statistics for debugging
  def stats : Hash(String, String | Int32)
    {
      "platform" => @platform_info["os"],
      "initialized" => @initialized,
      "shutdown" => @shutdown,
      "pending_requests" => @requests_sent.size,
      "next_request_id" => @max_request_id.get.to_i32
    }
  end

  # Send a request to the client and track it
  def send_request(method : String, params = nil) : RequestMessage::RequestId
    request_id = @max_request_id.add(1)
    request = LSP::RequestMessage.new(
      id: request_id,
      method: method,
      params: params
    )
    send(request)
    request_id
  end

  # Send a notification to the client
  def send_notification(method : String, params = nil)
    notification = LSP::NotificationMessage.new(
      method: method,
      params: params
    )
    send(notification)
  end

  # Graceful shutdown
  def shutdown
    @shutdown = true
    Log.info { "Server shutdown initiated" }
  end
end
