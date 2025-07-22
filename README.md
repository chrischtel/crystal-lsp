# `crystal-lsp` - Windows-Compatible Language Server Protocol

[![ci](https://github.com/elbywan/crystal-lsp/actions/workflows/ci.yml/badge.svg)](https://github.com/elbywan/crystal-lsp/actions/workflows/ci.yml)
[![docs](https://img.shields.io/badge/%F0%9F%93%9A-Crystal%20docs-blueviolet)](https://elbywan.github.io/crystal-lsp/)

### A comprehensive Language Server Protocol implementation written in Crystal with enhanced Windows compatibility.

This shard provides a **full-featured** implementation of the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) with special focus on Windows compatibility. It includes robust JSON mappings, platform-specific optimizations, and a complete server implementation.

## 🎯 Windows Compatibility Features

- **Path & URI Handling**: Proper Windows path normalization and file:// URI conversion
- **Line Ending Support**: Automatic CRLF/LF detection and handling
- **I/O Optimizations**: Windows-specific blocking/non-blocking I/O handling
- **Error Recovery**: Enhanced error handling for Windows-specific I/O issues
- **Unicode Support**: Proper UTF-8 text handling across platforms
- **File Operations**: Cross-platform file system operations

## 🚀 Key Features

- ✅ Complete LSP 3.17 specification support
- ✅ Windows path and URI handling
- ✅ Incremental text synchronization
- ✅ Robust error handling and recovery
- ✅ Platform-specific optimizations
- ✅ Comprehensive text document management
- ✅ File watching and workspace management
- ✅ Async message processing
- ✅ Enhanced logging and debugging

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     lsp:
       github: elbywan/crystal-lsp
   ```

2. Run `shards install`

## Usage

### Basic Server Setup

```crystal
require "lsp"

# Create server with Windows-optimized defaults
server = LSP.create_server(STDIN, STDOUT)

# Create your controller
controller = MyController.new

# Start the server
server.start(controller)
```

### Windows-Compatible Controller

```crystal
require "lsp/server"

class MyController
  # Text document manager with Windows compatibility
  private getter document_manager = LSP::TextDocumentManager.new
  
  # Called after the initialize request
  def on_init(params : LSP::InitializeParams) : LSP::InitializeResult?
    # Setup workspace with proper URI handling
    if root_uri = params.root_uri
      normalized_uri = LSP.normalize_file_uri(root_uri)
      # Handle Windows paths properly...
    end
    
    # Return capabilities
    LSP::InitializeResult.new(capabilities: my_capabilities)
  end

  # Handle text document operations
  def on_notification(notification : LSP::NotificationMessage)
    case notification.method
    when "textDocument/didOpen"
      params = notification.params.as(LSP::DidOpenTextDocumentParams)
      document_manager.open(
        uri: params.text_document.uri,
        language_id: params.text_document.language_id,
        version: params.text_document.version,
        content: params.text_document.text
      )
    when "textDocument/didChange"
      params = notification.params.as(LSP::DidChangeTextDocumentParams)
      document_manager.change(
        uri: params.text_document.uri,
        version: params.text_document.version,
        changes: params.content_changes
      )
    end
  end

  # Handle requests
  def on_request(request : LSP::RequestMessage)
    case request.method
    when "textDocument/hover"
      # Implement hover with proper Windows path handling
      handle_hover(request.params.as(LSP::HoverParams))
    when "textDocument/completion"
      # Implement completion
      handle_completion(request.params.as(LSP::CompletionParams))
    end
  end
end
```

### Platform-Specific Utilities

```crystal
# Path and URI utilities
file_path = "C:\\Users\\example\\file.txt"
file_uri = LSP.path_to_uri(file_path)  # => "file:///C:/Users/example/file.txt"
converted_back = LSP.uri_to_path(file_uri)  # => "C:\Users\example\file.txt"

# Platform detection
if LSP.windows?
  puts "Running on Windows with CRLF line endings"
else
  puts "Running on Unix-like system"
end

# Text document management
doc_manager = LSP::TextDocumentManager.new
doc_manager.open("file:///C:/path/to/file.cr", "crystal", 1, content)

# Platform-aware operations
normalized_path = LSP::Platform.normalize_path(user_input_path)
absolute_path = LSP::Platform.expand_path(relative_path)
```

## 🏗️ Architecture

The Windows-compatible LSP implementation consists of several key components:

- **`LSP::Server`** - Enhanced server with Windows I/O optimizations
- **`LSP::Platform`** - Cross-platform utilities and Windows-specific helpers
- **`LSP::URIUtils`** - Windows-compatible URI and path handling
- **`LSP::IO`** - Robust I/O utilities with timeout and error handling
- **`LSP::TextDocumentManager`** - Comprehensive text document state management

## 🔧 Configuration

### Server Capabilities

```crystal
capabilities = LSP::ServerCapabilities.new(
  text_document_sync: LSP::TextDocumentSyncOptions.new(
    open_close: true,
    change: LSP::TextDocumentSyncKind::Incremental,
    save: LSP::SaveOptions.new(include_text: false)
  ),
  hover_provider: true,
  completion_provider: LSP::CompletionOptions.new(
    trigger_characters: ["."],
    resolve_provider: true
  ),
  # Enhanced workspace support
  workspace: LSP::WorkspaceServerCapabilities.new(
    workspace_folders: LSP::WorkspaceFoldersServerCapabilities.new(
      supported: true,
      change_notifications: true
    )
  )
)
```

### Logging Setup

```crystal
# Enable debug logging for development
Log.setup(:debug, Log::IOBackend.new(STDERR))

# Or log to file with Windows-compatible path
log_file = LSP::Platform.windows? ? ".\\lsp.log" : "./lsp.log"
Log.setup(:info, Log::IOBackend.new(File.new(log_file, "a+")))
```

## 🧪 Testing

Run the test suite:

```bash
crystal spec
```

Test Windows compatibility specifically:

```bash
# On Windows
crystal run examples/windows_compatible_controller.cr -- --example

# Test file operations
crystal spec spec/platform_spec.cr
crystal spec spec/uri_utils_spec.cr
```

## 📋 Windows-Specific Considerations

### File Paths
- Handles both forward and backward slashes
- Proper drive letter normalization (C:\ vs C:/)
- UNC path support (\\server\share)
- Case-insensitive path comparison

### Line Endings
- Automatic CRLF/LF detection
- Proper text document synchronization
- Platform-appropriate formatting

### I/O Operations
- Windows-specific timeout handling
- Enhanced error recovery
- Proper non-blocking I/O setup

### URI Handling
- Correct file:// URI encoding for Windows paths
- Proper percent-encoding/decoding
- Cross-platform URI normalization

## 🤝 Contributing

1. Fork it (<https://github.com/elbywan/crystal-lsp/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/elbywan/crystal-lsp.git
cd crystal-lsp

# Install dependencies
shards install

# Run tests
crystal spec

# Build examples
crystal build examples/windows_compatible_controller.cr

# Generate documentation
crystal docs
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

## 👥 Contributors

- [Julien Elbaz](https://github.com/elbywan) - creator and maintainer
- [Windows compatibility enhancements] - Enhanced Windows support and platform-specific optimizations

## 📚 References

- [Language Server Protocol Specification](https://microsoft.github.io/language-server-protocol/)
- [Crystal Language Documentation](https://crystal-lang.org/docs/)
- [Crystalline Language Server](https://github.com/elbywan/crystalline) - Reference implementation
