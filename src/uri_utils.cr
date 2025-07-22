require "uri"
require "./platform"

module LSP
  # Windows-compatible URI utilities for LSP file operations
  module URIUtils
    # Convert a file path to a proper file:// URI
    def self.path_to_uri(path : String) : String
      # Return as-is if already a URI
      return path if path.starts_with?("file://") || path.includes?("://")

      # Normalize the path first
      normalized = LSP::Platform.normalize_path(path)

      if LSP::Platform.windows?
        # Handle Windows-specific path to URI conversion
        path_to_uri_windows(normalized)
      else
        # Handle Unix-like path to URI conversion
        path_to_uri_unix(normalized)
      end
    end

    # Convert a file:// URI to a file path
    def self.uri_to_path(uri : String) : String
      # Return as-is if not a file URI
      return uri unless uri.starts_with?("file://")

      if LSP::Platform.windows?
        uri_to_path_windows(uri)
      else
        uri_to_path_unix(uri)
      end
    end

    # Normalize a URI for cross-platform compatibility
    def self.normalize_uri(uri : String) : String
      return uri unless uri.starts_with?("file://")

      # Convert to path and back to URI for normalization
      path = uri_to_path(uri)
      path_to_uri(path)
    end

    # Check if two URIs refer to the same file (platform-aware)
    def self.uris_equal?(uri1 : String, uri2 : String) : Bool
      # Convert to paths for comparison
      path1 = uri_to_path(uri1)
      path2 = uri_to_path(uri2)

      LSP::Platform.paths_equal?(path1, path2)
    end

    # Get the directory URI for a file URI
    def self.dirname_uri(uri : String) : String
      path = uri_to_path(uri)
      dir_path = LSP::Platform.dirname(path)
      path_to_uri(dir_path)
    end

    # Get the basename from a URI
    def self.basename_uri(uri : String) : String
      path = uri_to_path(uri)
      LSP::Platform.basename(path)
    end

    # Join URI paths
    def self.join_uri(base_uri : String, *components : String) : String
      base_path = uri_to_path(base_uri)
      joined_path = LSP::Platform.join_path(base_path, *components)
      path_to_uri(joined_path)
    end

    # Check if a URI represents an absolute path
    def self.absolute_uri?(uri : String) : Bool
      return true if uri.includes?("://")

      path = uri_to_path(uri)
      LSP::Platform.absolute_path?(path)
    end

    # Get file extension from URI
    def self.extname_uri(uri : String) : String
      path = uri_to_path(uri)
      LSP::Platform.extname(path)
    end

    # Windows-specific path to URI conversion
    private def self.path_to_uri_windows(path : String) : String
      # Handle different Windows path formats
      if path.matches?(/^[a-zA-Z]:/)
        # Drive letter path: C:\path\to\file -> file:///C:/path/to/file
        drive_path = path.gsub('\\', '/')
        "file:///#{drive_path}"
      elsif path.starts_with?("\\\\")
        # UNC path: \\server\share\path -> file://server/share/path
        unc_path = path[2..].gsub('\\', '/')
        "file://#{unc_path}"
      else
        # Relative or other path
        normalized = path.gsub('\\', '/')
        if normalized.starts_with?("/")
          "file://#{normalized}"
        else
          "file:///#{normalized}"
        end
      end
    end

    # Unix-specific path to URI conversion
    private def self.path_to_uri_unix(path : String) : String
      # Ensure forward slashes
      normalized = path.gsub('\\', '/')

      if normalized.starts_with?("/")
        "file://#{normalized}"
      else
        # Relative path - make it absolute first
        absolute = LSP::Platform.expand_path(normalized)
        "file://#{absolute}"
      end
    end

    # Windows-specific URI to path conversion
    private def self.uri_to_path_windows(uri : String) : String
      # Remove file:// prefix
      path = URI.decode(uri.sub(/^file:\/\//, ""))

      # Handle different URI formats
      if path.matches?(/^\/[a-zA-Z]:/)
        # file:///C:/path/to/file -> C:\path\to\file
        path[1..].gsub('/', '\\')
      elsif path.matches?(/^[a-zA-Z]:/)
        # file://C:/path/to/file -> C:\path\to\file (malformed but handle it)
        path.gsub('/', '\\')
      elsif path.starts_with?("/") && !path.starts_with?("//")
        # file:///path -> \path (unusual on Windows but handle it)
        path.gsub('/', '\\')
      else
        # UNC or other format
        path.gsub('/', '\\')
      end
    end

    # Unix-specific URI to path conversion
    private def self.uri_to_path_unix(uri : String) : String
      # Remove file:// prefix and decode
      path = URI.decode(uri.sub(/^file:\/\//, ""))

      # Ensure it starts with / for absolute paths
      if path.empty? || !path.starts_with?("/")
        "/#{path}"
      else
        path
      end
    end

    # Validate that a string is a proper URI
    def self.valid_uri?(uri : String) : Bool
      return false if uri.empty?

      # Check for URI scheme
      return true if uri.includes?("://")

      # Check if it's a valid file path that can be converted
      begin
        path_to_uri(uri)
        true
      rescue
        false
      end
    end

    # Create a workspace folder URI from a path
    def self.workspace_uri(path : String) : String
      # Ensure the path is absolute
      absolute_path = if LSP::Platform.absolute_path?(path)
                       path
                     else
                       LSP::Platform.expand_path(path)
                     end

      path_to_uri(absolute_path)
    end

    # Extract scheme from URI
    def self.scheme(uri : String) : String?
      if match = uri.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/)
        match[1]
      else
        nil
      end
    end

    # Check if URI has a specific scheme
    def self.has_scheme?(uri : String, scheme : String) : Bool
      uri_scheme = self.scheme(uri)
      return false unless uri_scheme

      uri_scheme.downcase == scheme.downcase
    end

    # Get relative path from base URI to target URI
    def self.relative_uri(base_uri : String, target_uri : String) : String?
      return nil unless has_scheme?(base_uri, "file") && has_scheme?(target_uri, "file")

      base_path = uri_to_path(base_uri)
      target_path = uri_to_path(target_uri)

      # Simple relative path calculation
      # This is a basic implementation - could be enhanced
      if target_path.starts_with?(base_path)
        relative = target_path[base_path.size..]
        relative = relative[1..] if relative.starts_with?(LSP::Platform.windows? ? "\\" : "/")
        relative
      else
        nil
      end
    end
  end
end
