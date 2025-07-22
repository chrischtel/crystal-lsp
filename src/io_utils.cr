require "json"
require "./platform"

module LSP
  # Windows-compatible I/O utilities for LSP communication
  module IO
    # Read LSP message from IO with Windows compatibility
    def self.read_message(io : ::IO) : LSP::Message
      # Set appropriate blocking behavior based on platform
      setup_io_blocking(io)

      content_length = nil
      content_type = "application/vscode-jsonrpc; charset=utf-8"

      # Read headers
      loop do
        header_line = read_line_with_timeout(io)
        break if header_line.nil?

        header = header_line.chomp.chomp('\r')  # Handle both LF and CRLF
        break if header.empty?

        if header.includes?(':')
          name, value = header.split(':', 2)
          name = name.strip
          value = value.strip

          case name
          when "Content-Length"
            content_length = value.to_i?
            raise "Invalid Content-Length: #{value}" if content_length.nil?
          when "Content-Type"
            content_type = value
          else
            # LSP spec allows unknown headers to be ignored
            Log.debug { "Ignoring unknown header: #{name}" }
          end
        end
      end

      raise "Content-Length header is required" if content_length.nil? || content_length.not_nil! <= 0

      # Read content
      content = read_content_with_timeout(io, content_length.not_nil!)
      content_str = String.new(content)

      # Parse JSON message with proper error handling
      parse_lsp_message(content_str)
    end

    # Write LSP message to IO with Windows compatibility
    def self.write_message(io : ::IO, message : LSP::Message) : Nil
      json = message.to_json
      line_ending = LSP::Platform.line_ending

      # Write headers with platform-appropriate line endings
      header = "Content-Length: #{json.bytesize}#{line_ending}#{line_ending}#{json}"

      io.write(header.to_slice)
      io.flush
    end

    # Setup IO blocking behavior based on platform
    private def self.setup_io_blocking(io : ::IO)
      return unless io.responds_to?(:blocking)

      # On Windows, only set non-blocking for non-STDIN streams
      if LSP::Platform.windows?
        io.blocking = false unless io.same?(STDIN)
      else
        io.blocking = false
      end
    rescue ex
      Log.warn { "Failed to set IO blocking mode: #{ex.message}" }
    end

    # Read a line with timeout handling
    private def self.read_line_with_timeout(io : ::IO, timeout_seconds : Int32 = 30) : String?
      if LSP::Platform.windows?
        # Windows-specific timeout handling
        read_line_windows(io, timeout_seconds)
      else
        # Unix-like timeout handling
        read_line_unix(io, timeout_seconds)
      end
    end

    # Windows-specific line reading with timeout
    private def self.read_line_windows(io : ::IO, timeout : Int32) : String?
      start_time = Time.monotonic
      buffer = String::Builder.new

      loop do
        # Check for timeout
        if (Time.monotonic - start_time).total_seconds > timeout
          raise ::IO::TimeoutError.new("Read timeout after #{timeout} seconds")
        end

        begin
          char = io.read_char
          return nil if char.nil?

          if char == '\n'
            return buffer.to_s
          elsif char == '\r'
            # Peek for LF to handle CRLF properly
            next_char = io.read_char
            if next_char == '\n'
              return buffer.to_s
            else
              # Put back the character if it's not LF
              if next_char && io.responds_to?(:unread)
                io.unread(next_char.to_s.to_slice)
              end
              return buffer.to_s
            end
          else
            buffer << char
          end
        rescue ex : ::IO::Error
          # Handle non-blocking I/O that would block
          if ex.message.try(&.includes?("would block")) || ex.message.try(&.includes?("temporarily unavailable"))
            # Non-blocking IO would block, wait a bit
            sleep(1.millisecond)
          else
            raise ex
          end
        end
      end
    rescue ex : ::IO::Error
      return nil
    end

    # Unix-specific line reading with timeout
    private def self.read_line_unix(io : ::IO, timeout : Int32) : String?
      io.gets(chomp: false)
    rescue ::IO::TimeoutError | ::IO::Error
      nil
    end

    # Read exact amount of content with timeout
    private def self.read_content_with_timeout(io : ::IO, length : Int32, timeout_seconds : Int32 = 30) : Bytes
      content = Bytes.new(length)
      bytes_read = 0
      start_time = Time.monotonic

      while bytes_read < length
        # Check for timeout
        if (Time.monotonic - start_time).total_seconds > timeout_seconds
          raise ::IO::TimeoutError.new("Read timeout after #{timeout_seconds} seconds")
        end

        begin
          chunk_size = io.read(content[bytes_read..])
          raise ::IO::Error.new("Unexpected end of input") if chunk_size == 0
          bytes_read += chunk_size
        rescue ex : ::IO::Error
          # Handle non-blocking I/O that would block
          if ex.message.try(&.includes?("would block")) || ex.message.try(&.includes?("temporarily unavailable"))
            # Non-blocking IO would block, wait a bit
            sleep(1.millisecond) if LSP::Platform.windows?
          else
            raise ex
          end
        end
      end

      content
    end

    # Parse LSP message with proper type detection
    private def self.parse_lsp_message(content : String) : LSP::Message
      # Log the incoming message
      Log.debug { "[Client -> Server] #{content}" }

      # Try to parse as different message types in order of specificity
      begin
        # Try RequestMessage first (most specific)
        return LSP::RequestMessage.from_json(content)
      rescue JSON::ParseException
        # Fall back to ResponseMessage
        begin
          return LSP::ResponseMessage(JSON::Any?).from_json(content)
        rescue JSON::ParseException
          # Fall back to NotificationMessage
          return LSP::NotificationMessage.from_json(content)
        end
      end
    rescue ex : JSON::ParseException
      raise LSP::Exception.new(
        code: :parse_error,
        message: "Invalid JSON content: #{ex.message}"
      )
    end

    # Safe IO close with error handling
    def self.safe_close(io : ::IO?) : Nil
      return if io.nil?

      begin
        io.close unless io.closed?
      rescue ex
        Log.warn { "Error closing IO: #{ex.message}" }
      end
    end

    # Check if IO is still connected
    def self.connected?(io : ::IO) : Bool
      return false if io.closed?

      begin
        # Try to read 0 bytes to test connection
        io.read(Bytes.new(0))
        true
      rescue ::IO::Error
        false
      end
    end

    # Flush IO with error handling
    def self.safe_flush(io : ::IO) : Nil
      begin
        io.flush
      rescue ex
        Log.warn { "Error flushing IO: #{ex.message}" }
      end
    end
  end
end
