require "../src/lsp"
require "../src/server"

# Enhanced example controller with Windows compatibility features
class WindowsCompatibleController
  # Text document manager for tracking open files
  private getter document_manager = LSP::TextDocumentManager.new

  # Track workspace folders
  private getter workspace_folders = Array(LSP::WorkspaceFolder).new

  # Server reference for sending notifications/requests
  property! server : LSP::Server

  def initialize
    Log.info { "Windows-compatible LSP controller initialized" }
  end

  # Called when server is ready
  def when_ready
    # Server reference should be set by now, but let's be safe
    if @server
      Log.info { "Controller ready with server connection" }
    else
      Log.warn { "Controller ready but server reference not set" }
    end
  end  # Called after the initialize request
  def on_init(params : LSP::InitializeParams) : LSP::InitializeResult?
    Log.info { "Client initializing..." }
    Log.debug { "Client info: #{params.client_info.try(&.[:name])} #{params.client_info.try(&.[:version])}" }

    # Store workspace information
    if workspace_folders = params.workspace_folders
      @workspace_folders.concat(workspace_folders)
      Log.info { "Workspace folders: #{workspace_folders.map(&.uri)}" }
    elsif root_uri = params.root_uri
      # Legacy single root support
      folder = LSP::WorkspaceFolder.new(
        uri: LSP::URIUtils.normalize_uri(root_uri),
        name: LSP::URIUtils.basename_uri(root_uri)
      )
      @workspace_folders << folder
      Log.info { "Root workspace: #{root_uri}" }
    end

    # Return enhanced initialization result
    LSP::InitializeResult.new(
      capabilities: enhanced_server_capabilities,
      server_info: {
        name: "Windows-Compatible Crystal LSP",
        version: LSP::VERSION
      }
    )
  end

  # Called when the server is ready to receive requests
  def when_ready
    Log.info { "Server ready - Windows compatibility features enabled" }

    # Send platform info to client via log message
    platform_info = LSP.platform_info
    server.send_notification("window/logMessage", LSP::LogMessageParams.new(
      type: LSP::MessageType::Info,
      message: "LSP Server running on #{platform_info["os"]} with Crystal #{platform_info["crystal_version"]}"
    ))
  end

  # Handle incoming requests
  def on_request(request : LSP::RequestMessage)
    Log.debug { "Processing request: #{request.method}" }

    case request.method
    when "textDocument/hover"
      handle_hover(request.as(LSP::HoverRequest).params)
    when "textDocument/completion"
      handle_completion(request.as(LSP::CompletionRequest).params)
    when "textDocument/definition"
      handle_definition(request.as(LSP::DefinitionRequest).params)
    when "textDocument/documentSymbol"
      handle_document_symbols(request.as(LSP::DocumentSymbolsRequest).params)
    when "textDocument/formatting"
      handle_formatting(request.as(LSP::DocumentFormattingRequest).params)
    else
      Log.warn { "Unhandled request method: #{request.method}" }
      nil
    end
  end

  # Handle incoming notifications
  def on_notification(notification : LSP::NotificationMessage)
    Log.debug { "Processing notification: #{notification.method}" }

    case notification.method
    when "textDocument/didOpen"
      handle_did_open(notification.as(LSP::DidOpenNotification).params)
    when "textDocument/didChange"
      handle_did_change(notification.as(LSP::DidChangeNotification).params)
    when "textDocument/didSave"
      handle_did_save(notification.as(LSP::DidSaveNotification).params)
    when "textDocument/didClose"
      handle_did_close(notification.as(LSP::DidCloseNotification).params)
    else
      Log.debug { "Unhandled notification: #{notification.method}" }
    end
  end

  # Handle server responses
  def on_response(response : LSP::ResponseMessage, original_request : LSP::RequestMessage?)
    Log.debug { "Received response for request #{response.id}" }

    if response.error
      Log.error { "Request failed: #{response.error.try(&.message)}" }
    end
  end

  # Called during server shutdown
  def on_shutdown
    Log.info { "Controller shutting down..." }
    document_manager.clear
    @workspace_folders.clear
  end

  # Enhanced server capabilities with Windows-specific features
  private def enhanced_server_capabilities : LSP::ServerCapabilities
    LSP::ServerCapabilities.new(
      text_document_sync: LSP::TextDocumentSyncOptions.new(
        open_close: true,
        change: LSP::TextDocumentSyncKind::Incremental
      ),
      hover_provider: true,
      completion_provider: LSP::CompletionOptions.new(
        trigger_characters: ["."],
        resolve_provider: true
      ),
      definition_provider: true,
      document_symbol_provider: true,
      document_formatting_provider: true,
      workspace: LSP::WorkspaceValue.new(
        workspace_folders: LSP::WorkspaceFoldersServerCapabilities.new(
          supported: true,
          change_notifications: true
        )
      )
    )
  end

  # Text Document Handlers

  private def handle_did_open(params : LSP::DidOpenTextDocumentParams)
    doc = params.text_document
    Log.info { "Document opened: #{doc.uri}" }

    document_manager.open(
      uri: doc.uri,
      language_id: doc.language_id,
      version: doc.version,
      content: doc.text
    )

    # Perform initial validation
    validate_document(doc.uri)
  end

  private def handle_did_change(params : LSP::DidChangeTextDocumentParams)
    doc = params.text_document
    Log.debug { "Document changed: #{doc.uri} (version #{doc.version})" }

    document_manager.change(
      uri: doc.uri,
      version: doc.version || 0,
      changes: params.content_changes
    )

    # Re-validate document
    validate_document(doc.uri)
  end

  private def handle_did_save(params : LSP::DidSaveTextDocumentParams)
    Log.debug { "Document saved: #{params.text_document.uri}" }

    # Perform full validation on save
    validate_document(params.text_document.uri)
  end

  private def handle_did_close(params : LSP::DidCloseTextDocumentParams)
    Log.info { "Document closed: #{params.text_document.uri}" }

    document_manager.close(params.text_document.uri)

    # Clear diagnostics for closed document
    server.send_notification("textDocument/publishDiagnostics",
      LSP::PublishDiagnosticsParams.new(
        uri: params.text_document.uri,
        diagnostics: [] of LSP::Diagnostic
      )
    )
  end

  # Language Feature Handlers

  private def handle_hover(params : LSP::HoverParams) : LSP::Hover?
    uri = params.text_document.uri
    position = params.position

    Log.debug { "Hover request for #{uri} at #{position.line}:#{position.character}" }

    # Get word at position
    word = get_word_at_position(uri, position)
    return nil unless word

    # Return example hover information
    LSP::Hover.new(
      contents: LSP::MarkupContent.new(
        kind: LSP::MarkupKind::MarkDown,
        value: "**#{word}**\n\nWindows-compatible hover information"
      ),
      range: get_word_range(uri, position)
    )
  end

  private def handle_completion(params : LSP::CompletionParams) : LSP::CompletionList
    uri = params.text_document.uri
    position = params.position

    Log.debug { "Completion request for #{uri} at #{position.line}:#{position.character}" }

    # Example completion items
    items = [
      LSP::CompletionItem.new(
        label: "puts",
        kind: LSP::CompletionItemKind::Function,
        detail: "Print to stdout",
        documentation: "Windows-compatible print function"
      ),
      LSP::CompletionItem.new(
        label: "File.read",
        kind: LSP::CompletionItemKind::Method,
        detail: "Read file content",
        documentation: "Cross-platform file reading"
      )
    ]

    LSP::CompletionList.new(
      is_incomplete: false,
      items: items
    )
  end

  private def handle_definition(params : LSP::DefinitionParams) : Array(LSP::Location)?
    uri = params.text_document.uri
    position = params.position

    Log.debug { "Definition request for #{uri} at #{position.line}:#{position.character}" }

    # Example: return the same location (placeholder implementation)
    [LSP::Location.new(
      uri: uri,
      range: LSP::Range.new(
        start: position,
        end: position
      )
    )]
  end

  private def handle_document_symbols(params : LSP::DocumentSymbolParams) : Array(LSP::DocumentSymbol)
    uri = params.text_document.uri

    Log.debug { "Document symbols request for #{uri}" }

    content = document_manager.content(uri)
    return [] of LSP::DocumentSymbol unless content

    # Example: find class/method definitions
    symbols = [] of LSP::DocumentSymbol
    lines = content.split(/\r?\n/)

    lines.each_with_index do |line, index|
      if match = line.match(/^\s*class\s+(\w+)/)
        symbols << create_symbol(match[1], LSP::SymbolKind::Class, index, line)
      elsif match = line.match(/^\s*def\s+(\w+)/)
        symbols << create_symbol(match[1], LSP::SymbolKind::Method, index, line)
      end
    end

    symbols
  end

  private def handle_formatting(params : LSP::DocumentFormattingParams) : Array(LSP::TextEdit)?
    uri = params.text_document.uri

    Log.debug { "Formatting request for #{uri}" }

    content = document_manager.content(uri)
    return nil unless content

    # Example: ensure proper line endings for platform
    line_ending = LSP::Platform.line_ending
    current_line_ending = document_manager.line_endings(uri) || "\n"

    if line_ending != current_line_ending
      formatted_content = content.gsub(/\r?\n/, line_ending)

      # Return edit that replaces entire document
      [LSP::TextEdit.new(
        range: LSP::Range.new(
          start: LSP::Position.new(line: 0, character: 0),
          end: LSP::Position.new(
            line: document_manager.line_count(uri).try(&.- 1) || 0,
            character: content.split(/\r?\n/).last.size
          )
        ),
        new_text: formatted_content
      )]
    else
      # No formatting needed
      [] of LSP::TextEdit
    end
  end

  # Helper Methods

  private def validate_document(uri : String)
    content = document_manager.content(uri)
    return unless content

    # Example validation: check for basic syntax issues
    diagnostics = [] of LSP::Diagnostic

    # Check for mixed line endings (common Windows issue)
    if content.includes?("\r\n") && content.includes?("\n")
      line_ending_mixed = content.scan(/\r?\n/).map(&.[0]).uniq.size > 1
      if line_ending_mixed
        diagnostics << LSP::Diagnostic.new(
          range: LSP::Range.new(
            start: LSP::Position.new(line: 0, character: 0),
            end: LSP::Position.new(line: 0, character: 0)
          ),
          severity: LSP::DiagnosticSeverity::Warning.value,
          message: "Mixed line endings detected. Consider using consistent line endings for better cross-platform compatibility.",
          source: "crystal-lsp"
        )
      end
    end

    # Send diagnostics to client
    server.send_notification("textDocument/publishDiagnostics",
      LSP::PublishDiagnosticsParams.new(
        uri: uri,
        diagnostics: diagnostics
      )
    )
  end

  private def get_word_at_position(uri : String, position : LSP::Position) : String?
    line_content = document_manager.line_content(uri, position.line)
    return nil unless line_content

    # Simple word extraction
    words = line_content.split(/\W+/)
    current_pos = 0

    words.each do |word|
      word_start = line_content.index(word, current_pos)
      next unless word_start

      word_end = word_start + word.size
      if position.character >= word_start && position.character <= word_end
        return word
      end

      current_pos = word_end
    end

    nil
  end

  private def get_word_range(uri : String, position : LSP::Position) : LSP::Range?
    line_content = document_manager.line_content(uri, position.line)
    return nil unless line_content

    # Find word boundaries
    start_char = position.character
    end_char = position.character

    # Move start backward
    while start_char > 0 && line_content[start_char - 1].alphanumeric?
      start_char -= 1
    end

    # Move end forward
    while end_char < line_content.size && line_content[end_char].alphanumeric?
      end_char += 1
    end

    LSP::Range.new(
      start: LSP::Position.new(line: position.line, character: start_char),
      end: LSP::Position.new(line: position.line, character: end_char)
    )
  end

  private def create_symbol(name : String, kind : LSP::SymbolKind, line : Int32, line_content : String) : LSP::DocumentSymbol
    LSP::DocumentSymbol.new(
      name: name,
      kind: kind,
      range: LSP::Range.new(
        start: LSP::Position.new(line: line, character: 0),
        end: LSP::Position.new(line: line, character: line_content.size)
      ),
      selection_range: LSP::Range.new(
        start: LSP::Position.new(line: line, character: line_content.index(name) || 0),
        end: LSP::Position.new(line: line, character: (line_content.index(name) || 0) + name.size)
      )
    )
  end
end

# Example usage
if ARGV.includes?("--example")
  Log.setup(:debug, Log::IOBackend.new(STDERR))

  controller = WindowsCompatibleController.new
  server = LSP.create_server
  controller.server = server

  puts "Starting Windows-compatible LSP server..."
  puts "Platform: #{LSP.platform_info["os"]}"
  puts "Press Ctrl+C to stop"

  server.start(controller)
end
