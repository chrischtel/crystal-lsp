require "./platform"
require "./uri_utils"
require "./io_utils"
require "./text_document_manager"

module LSP
  VERSION = "0.2.0"

  # Windows-compatible LSP implementation
  #
  # This module provides a comprehensive Language Server Protocol implementation
  # optimized for Windows compatibility while maintaining cross-platform support.
  #
  # Key features:
  # - Proper Windows path and URI handling
  # - CRLF line ending support
  # - Enhanced I/O error handling
  # - Platform-specific optimizations
  # - Robust text document management
  # - Unicode-aware text operations

  # Get platform information
  def self.platform_info : Hash(String, String)
    {
      "os" => Platform.windows? ? "Windows" : "Unix",
      "version" => VERSION,
      "crystal_version" => Crystal::VERSION,
      "line_ending" => Platform.line_ending.inspect
    }
  end

  # Check if running on Windows
  def self.windows? : Bool
    Platform.windows?
  end

  # Create a new server instance with Windows-optimized defaults
  def self.create_server(input : ::IO = STDIN, output : ::IO = STDOUT, capabilities : ServerCapabilities? = nil) : Server
    server_capabilities = capabilities || Server::DEFAULT_SERVER_CAPABILITIES
    Server.new(input, output, server_capabilities)
  end

  # Utility method to normalize file URIs for the current platform
  def self.normalize_file_uri(uri : String) : String
    URIUtils.normalize_uri(uri)
  end

  # Utility method to convert file path to URI
  def self.path_to_uri(path : String) : String
    URIUtils.path_to_uri(path)
  end

  # Utility method to convert URI to file path
  def self.uri_to_path(uri : String) : String
    URIUtils.uri_to_path(uri)
  end
end
