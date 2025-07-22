require "path"

module LSP::Platform
  # Detect the current platform
  def self.windows?
    {% if flag?(:win32) %}
      true
    {% else %}
      false
    {% end %}
  end

  def self.unix?
    !windows?
  end

  # Get the appropriate line ending for the platform
  def self.line_ending
    windows? ? "\r\n" : "\n"
  end

  # Normalize file paths for the platform
  def self.normalize_path(path : String) : String
    return path if path.starts_with?("file://")

    if windows?
      # Convert forward slashes to backslashes on Windows
      normalized = path.gsub('/', '\\')
      # Handle drive letters properly
      if normalized.matches?(/^[a-zA-Z]:/)
        return normalized
      elsif normalized.starts_with?("\\\\")
        # UNC path - leave as is
        return normalized
      else
        # Relative path
        return normalized
      end
    else
      # Unix-like systems - convert backslashes to forward slashes
      path.gsub('\\', '/')
    end
  end

  # Convert a file path to a proper URI
  def self.path_to_uri(path : String) : String
    return path if path.starts_with?("file://")

    normalized_path = normalize_path(path)

    if windows?
      # Handle Windows paths
      if normalized_path.matches?(/^[a-zA-Z]:/)
        # Drive letter path like C:\path\to\file
        "file:///#{normalized_path.gsub('\\', '/')}"
      elsif normalized_path.starts_with?("\\\\")
        # UNC path like \\server\share\path
        "file:#{normalized_path.gsub('\\', '/')}"
      else
        # Relative or other path
        "file:///#{normalized_path.gsub('\\', '/')}"
      end
    else
      # Unix-like systems
      if normalized_path.starts_with?("/")
        "file://#{normalized_path}"
      else
        "file:///#{normalized_path}"
      end
    end
  end

  # Convert a URI to a file path
  def self.uri_to_path(uri : String) : String
    return uri unless uri.starts_with?("file://")

    path = URI.decode(uri.sub("file://", ""))

    if windows?
      # Remove leading slash if it's a drive letter path
      if path.matches?(/^\/[a-zA-Z]:/)
        path = path[1..]
      end
      # Convert forward slashes to backslashes
      path.gsub('/', '\\')
    else
      # Ensure leading slash for Unix paths
      path.starts_with?("/") ? path : "/#{path}"
    end
  end

  # Check if a path is absolute
  def self.absolute_path?(path : String) : Bool
    if windows?
      # Windows absolute paths: C:\, \\server\share, or /C:/
      path.matches?(/^[a-zA-Z]:/) ||
      path.starts_with?("\\\\") ||
      path.matches?(/^\/[a-zA-Z]:/)
    else
      path.starts_with?("/")
    end
  end

  # Join path components
  def self.join_path(*components : String) : String
    separator = windows? ? "\\" : "/"
    Path.new(*components).to_s
  end

  # Get the directory name of a path
  def self.dirname(path : String) : String
    Path.new(path).parent.to_s
  end

  # Get the base name of a path
  def self.basename(path : String) : String
    Path.new(path).basename
  end

  # Get the file extension
  def self.extname(path : String) : String
    Path.new(path).extension
  end

  # Check if file exists
  def self.file_exists?(path : String) : Bool
    File.exists?(path)
  end

  # Check if directory exists
  def self.directory_exists?(path : String) : Bool
    Dir.exists?(path)
  end

  # Create directory recursively
  def self.create_directory(path : String) : Nil
    Dir.mkdir_p(path)
  end

  # Get current working directory
  def self.current_directory : String
    Dir.current
  end

  # Expand relative path to absolute
  def self.expand_path(path : String, base : String? = nil) : String
    Path.new(path).expand(base || current_directory).to_s
  end

  # Case-sensitive path comparison for the platform
  def self.paths_equal?(path1 : String, path2 : String) : Bool
    if windows?
      # Windows is case-insensitive
      normalize_path(path1).downcase == normalize_path(path2).downcase
    else
      # Unix is case-sensitive
      normalize_path(path1) == normalize_path(path2)
    end
  end
end
