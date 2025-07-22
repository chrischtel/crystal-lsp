require "./platform"
require "./uri_utils"
require "./notifications/text_synchronization/did_change"
require "log"

module LSP
  # Windows-compatible text document management
  class TextDocumentManager
    # Track open documents with their content and version
    private getter documents = Hash(String, DocumentState).new

    # Document state tracking
    private struct DocumentState
      property content : String
      property version : Int32
      property language_id : String
      property line_endings : String
      property encoding : String

      def initialize(@content : String, @version : Int32, @language_id : String)
        @line_endings = detect_line_endings(@content)
        @encoding = "utf-8"  # LSP always uses UTF-8
      end

      private def detect_line_endings(text : String) : String
        if text.includes?("\r\n")
          "\r\n"  # Windows (CRLF)
        elsif text.includes?("\r")
          "\r"    # Classic Mac (CR)
        else
          "\n"    # Unix (LF)
        end
      end
    end

    # Open a document
    def open(uri : String, language_id : String, version : Int32, content : String)
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      @documents[normalized_uri] = DocumentState.new(
        content: content,
        version: version,
        language_id: language_id
      )

      Log.debug { "Opened document: #{normalized_uri} (#{language_id}, version #{version})" }
    end

    # Close a document
    def close(uri : String)
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      if @documents.delete(normalized_uri)
        Log.debug { "Closed document: #{normalized_uri}" }
      else
        Log.warn { "Attempted to close unknown document: #{normalized_uri}" }
      end
    end

    # Update document content with incremental changes
    def change(uri : String, version : Int32, changes : Array(DidChangeTextDocumentParams::TextDocumentContentChangeEvent))
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      unless document = @documents[normalized_uri]?
        raise LSP::Exception.new(
          code: :invalid_params,
          message: "Document not found: #{normalized_uri}"
        )
      end

      # Validate version
      if version <= document.version
        Log.warn { "Received outdated version #{version} for #{normalized_uri} (current: #{document.version})" }
        return
      end

      # Apply changes
      new_content = apply_changes(document.content, changes)

      @documents[normalized_uri] = DocumentState.new(
        content: new_content,
        version: version,
        language_id: document.language_id
      )

      Log.debug { "Updated document: #{normalized_uri} to version #{version}" }
    end

    # Get document content
    def content(uri : String) : String?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)
      @documents[normalized_uri]?.try(&.content)
    end

    # Get document version
    def version(uri : String) : Int32?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)
      @documents[normalized_uri]?.try(&.version)
    end

    # Get document language ID
    def language_id(uri : String) : String?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)
      @documents[normalized_uri]?.try(&.language_id)
    end

    # Check if document is open
    def open?(uri : String) : Bool
      normalized_uri = LSP::URIUtils.normalize_uri(uri)
      @documents.has_key?(normalized_uri)
    end

    # Get all open document URIs
    def open_documents : Array(String)
      @documents.keys
    end

    # Get document line endings
    def line_endings(uri : String) : String?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)
      @documents[normalized_uri]?.try(&.line_endings)
    end

    # Get text at a specific range
    def text_in_range(uri : String, range : LSP::Range) : String?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      unless document = @documents[normalized_uri]?
        return nil
      end

      extract_text_range(document.content, range, document.line_endings)
    end

    # Get line content
    def line_content(uri : String, line : Int32) : String?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      unless document = @documents[normalized_uri]?
        return nil
      end

      lines = split_lines(document.content, document.line_endings)
      return nil if line < 0 || line >= lines.size

      lines[line]
    end

    # Get total line count
    def line_count(uri : String) : Int32?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      unless document = @documents[normalized_uri]?
        return nil
      end

      split_lines(document.content, document.line_endings).size
    end

    # Convert position to offset
    def position_to_offset(uri : String, position : LSP::Position) : Int32?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      unless document = @documents[normalized_uri]?
        return nil
      end

      lines = split_lines(document.content, document.line_endings)
      return nil if position.line < 0 || position.line >= lines.size

      offset = 0

      # Add length of all previous lines (including line endings)
      (0...position.line).each do |i|
        offset += lines[i].bytesize + document.line_endings.bytesize
      end

      # Add character offset within the target line
      line_content = lines[position.line]
      char_offset = [position.character, line_content.size].min
      offset += line_content[0, char_offset].bytesize

      offset
    end

    # Convert offset to position
    def offset_to_position(uri : String, offset : Int32) : LSP::Position?
      normalized_uri = LSP::URIUtils.normalize_uri(uri)

      unless document = @documents[normalized_uri]?
        return nil
      end

      return LSP::Position.new(line: 0, character: 0) if offset <= 0

      lines = split_lines(document.content, document.line_endings)
      current_offset = 0

      lines.each_with_index do |line, line_index|
        line_end_offset = current_offset + line.bytesize

        if offset <= line_end_offset
          # Position is within this line
          char_offset = offset - current_offset
          # Convert byte offset to character offset
          character = line[0, char_offset].size
          return LSP::Position.new(line: line_index, character: character)
        end

        # Move past this line and its line ending
        current_offset = line_end_offset + document.line_endings.bytesize
      end

      # Position is beyond the document
      last_line = lines.last? || ""
      LSP::Position.new(line: lines.size - 1, character: last_line.size)
    end

    # Apply incremental changes to document content
    private def apply_changes(content : String, changes : Array(DidChangeTextDocumentParams::TextDocumentContentChangeEvent)) : String
      # If there's a full document change, use it
      if full_change = changes.find(&.range.nil?)
        return full_change.text
      end

      # Apply incremental changes in reverse order to maintain positions
      result = content
      changes.sort_by! { |change|
        range = change.range.not_nil!
        {range.start.line, range.start.character}
      }.reverse!

      changes.each do |change|
        range = change.range.not_nil!
        result = apply_single_change(result, range, change.text)
      end

      result
    end

    # Apply a single change to content
    private def apply_single_change(content : String, range : LSP::Range, new_text : String) : String
      lines = split_lines(content, detect_line_endings(content))

      # Validate range
      return content if range.start.line < 0 || range.start.line >= lines.size
      return content if range.end.line < 0 || range.end.line >= lines.size

      # Calculate byte offsets
      start_offset = calculate_offset(lines, range.start)
      end_offset = calculate_offset(lines, range.end)

      # Replace the text
      before = content[0, start_offset]
      after = content[end_offset..]

      before + new_text + after
    end

    # Calculate byte offset for a position
    private def calculate_offset(lines : Array(String), position : LSP::Position) : Int32
      offset = 0
      line_ending_size = LSP::Platform.line_ending.bytesize

      # Add all complete lines before the target line
      (0...position.line).each do |i|
        offset += lines[i].bytesize + line_ending_size
      end

      # Add character offset within the target line
      if position.line < lines.size
        line = lines[position.line]
        char_offset = [position.character, line.size].min
        offset += line[0, char_offset].bytesize
      end

      offset
    end

    # Extract text within a range
    private def extract_text_range(content : String, range : LSP::Range, line_ending : String) : String
      lines = split_lines(content, line_ending)

      return "" if range.start.line < 0 || range.start.line >= lines.size
      return "" if range.end.line < 0 || range.end.line >= lines.size

      if range.start.line == range.end.line
        # Single line range
        line = lines[range.start.line]
        start_char = [range.start.character, 0].max
        end_char = [range.end.character, line.size].min
        return line[start_char, end_char - start_char]
      end

      # Multi-line range
      result = String::Builder.new

      # First line
      first_line = lines[range.start.line]
      start_char = [range.start.character, 0].max
      result << first_line[start_char..]
      result << line_ending

      # Middle lines
      ((range.start.line + 1)...range.end.line).each do |i|
        result << lines[i]
        result << line_ending
      end

      # Last line
      if range.end.line < lines.size
        last_line = lines[range.end.line]
        end_char = [range.end.character, last_line.size].min
        result << last_line[0, end_char]
      end

      result.to_s
    end

    # Split content into lines preserving line ending information
    private def split_lines(content : String, line_ending : String) : Array(String)
      if line_ending == "\r\n"
        content.split("\r\n")
      elsif line_ending == "\r"
        content.split("\r")
      else
        content.split("\n")
      end
    end

    # Detect line endings in text
    private def detect_line_endings(text : String) : String
      if text.includes?("\r\n")
        "\r\n"  # Windows (CRLF)
      elsif text.includes?("\r")
        "\r"    # Classic Mac (CR)
      else
        "\n"    # Unix (LF)
      end
    end

    # Get document statistics
    def stats : Hash(String, Int32)
      {
        "open_documents" => @documents.size,
        "total_content_size" => @documents.values.sum(&.content.bytesize),
      }
    end

    # Clean up all documents
    def clear
      @documents.clear
      Log.debug { "Cleared all documents" }
    end
  end
end
