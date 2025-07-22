require "./spec_helper"
require "../src/text_document_manager"
require "../src/notifications/text_synchronization/did_change"

describe LSP::TextDocumentManager do
  manager = LSP::TextDocumentManager.new
  test_uri = "file:///test/document.txt"
  test_content = "Line 1\nLine 2\r\nLine 3\n"

  describe "#open" do
    it "opens a document with correct state" do
      manager.open(test_uri, "plaintext", 1, test_content)

      manager.open?(test_uri).should be_true
      manager.content(test_uri).should eq(test_content)
      manager.version(test_uri).should eq(1)
      manager.language_id(test_uri).should eq("plaintext")
    end

    it "detects line endings correctly" do
      # Test Windows line endings
      windows_content = "Line 1\r\nLine 2\r\n"
      manager.open("file:///windows.txt", "plaintext", 1, windows_content)
      manager.line_endings("file:///windows.txt").should eq("\r\n")

      # Test Unix line endings
      unix_content = "Line 1\nLine 2\n"
      manager.open("file:///unix.txt", "plaintext", 1, unix_content)
      manager.line_endings("file:///unix.txt").should eq("\n")
    end
  end

  describe "#close" do
    it "closes an open document" do
      manager.open(test_uri, "plaintext", 1, test_content)
      manager.close(test_uri)

      manager.open?(test_uri).should be_false
      manager.content(test_uri).should be_nil
    end
  end

  describe "#change" do
    it "applies full document changes" do
      manager.open(test_uri, "plaintext", 1, test_content)

      new_content = "New content"
      changes = [LSP::DidChangeTextDocumentParams::TextDocumentContentChangeEvent.new(text: new_content)]

      manager.change(test_uri, 2, changes)

      manager.content(test_uri).should eq(new_content)
      manager.version(test_uri).should eq(2)
    end

    it "applies incremental changes" do
      content = "Hello World"
      manager.open(test_uri, "plaintext", 1, content)

      # Replace "World" with "Crystal"
      range = LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 6),
        end: LSP::Position.new(line: 0, character: 11)
      )

      changes = [LSP::DidChangeTextDocumentParams::TextDocumentContentChangeEvent.new(
        range: range,
        text: "Crystal"
      )]

      manager.change(test_uri, 2, changes)

      manager.content(test_uri).should eq("Hello Crystal")
    end

    it "handles multiple incremental changes" do
      content = "Line 1\nLine 2\nLine 3"
      manager.open(test_uri, "plaintext", 1, content)

      # Multiple changes
      changes = [
        LSP::DidChangeTextDocumentParams::TextDocumentContentChangeEvent.new(
          range: LSP::Range.new(
            start: LSP::Position.new(line: 0, character: 5),
            end: LSP::Position.new(line: 0, character: 6)
          ),
          text: " A"
        ),
        LSP::DidChangeTextDocumentParams::TextDocumentContentChangeEvent.new(
          range: LSP::Range.new(
            start: LSP::Position.new(line: 1, character: 5),
            end: LSP::Position.new(line: 1, character: 6)
          ),
          text: " B"
        )
      ]

      manager.change(test_uri, 2, changes)

      result = manager.content(test_uri)
      result.should contain("Line A")
      result.should contain("Line B")
    end
  end

  describe "#line_content" do
    it "returns correct line content" do
      manager.open(test_uri, "plaintext", 1, test_content)

      manager.line_content(test_uri, 0).should eq("Line 1")
      manager.line_content(test_uri, 1).should eq("Line 2")
      manager.line_content(test_uri, 2).should eq("Line 3")
    end

    it "handles out of bounds line numbers" do
      manager.open(test_uri, "plaintext", 1, test_content)

      manager.line_content(test_uri, -1).should be_nil
      manager.line_content(test_uri, 100).should be_nil
    end
  end

  describe "#line_count" do
    it "returns correct line count" do
      manager.open(test_uri, "plaintext", 1, test_content)
      manager.line_count(test_uri).should eq(3)
    end
  end

  describe "#text_in_range" do
    it "extracts text in range correctly" do
      content = "Hello\nWorld\nTest"
      manager.open(test_uri, "plaintext", 1, content)

      # Single line range
      range = LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 1),
        end: LSP::Position.new(line: 0, character: 4)
      )

      manager.text_in_range(test_uri, range).should eq("ell")
    end

    it "extracts multi-line range correctly" do
      content = "Hello\nWorld\nTest"
      manager.open(test_uri, "plaintext", 1, content)

      # Multi-line range
      range = LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 2),
        end: LSP::Position.new(line: 1, character: 3)
      )

      result = manager.text_in_range(test_uri, range)
      result.should contain("llo")
      result.should contain("Wor")
    end
  end

  describe "#position_to_offset" do
    it "converts position to byte offset correctly" do
      content = "Hello\nWorld"
      manager.open(test_uri, "plaintext", 1, content)

      # Position at start of second line
      position = LSP::Position.new(line: 1, character: 0)
      offset = manager.position_to_offset(test_uri, position)

      offset.should eq(6) # "Hello\n" = 6 bytes
    end
  end

  describe "#offset_to_position" do
    it "converts byte offset to position correctly" do
      content = "Hello\nWorld"
      manager.open(test_uri, "plaintext", 1, content)

      # Offset at start of second line
      position = manager.offset_to_position(test_uri, 6)

      position.should eq(LSP::Position.new(line: 1, character: 0))
    end
  end

  describe "Windows-specific line ending handling" do
    it "handles CRLF line endings correctly" do
      windows_content = "Line 1\r\nLine 2\r\nLine 3\r\n"
      manager.open(test_uri, "plaintext", 1, windows_content)

      manager.line_count(test_uri).should eq(4) # Empty line at end
      manager.line_content(test_uri, 0).should eq("Line 1")
      manager.line_content(test_uri, 1).should eq("Line 2")
      manager.line_content(test_uri, 2).should eq("Line 3")
    end

    it "handles mixed line endings" do
      mixed_content = "Line 1\r\nLine 2\nLine 3\r"
      manager.open(test_uri, "plaintext", 1, mixed_content)

      # Should detect CRLF as the primary line ending
      manager.line_endings(test_uri).should eq("\r\n")
    end
  end

  describe "#stats" do
    it "returns correct statistics" do
      manager.open(test_uri, "plaintext", 1, test_content)
      manager.open("file:///other.txt", "plaintext", 1, "other")

      stats = manager.stats
      stats["open_documents"].should eq(2)
      stats["total_content_size"].should be > 0
    end
  end

  describe "#clear" do
    it "clears all documents" do
      manager.open(test_uri, "plaintext", 1, test_content)
      manager.open("file:///other.txt", "plaintext", 1, "other")

      manager.clear

      manager.open_documents.should be_empty
      manager.stats["open_documents"].should eq(0)
    end
  end
end
