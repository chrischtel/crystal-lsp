require "./spec_helper"
require "../src/uri_utils"

describe LSP::URIUtils do
  describe ".path_to_uri" do
    it "converts Windows paths correctly" do
      if LSP::Platform.windows?
        path = "C:\\Users\\test\\file.txt"
        expected = "file:///C:/Users/test/file.txt"
      else
        path = "/home/user/file.txt"
        expected = "file:///home/user/file.txt"
      end

      result = LSP::URIUtils.path_to_uri(path)
      result.should eq(expected)
    end

    it "handles paths with spaces" do
      if LSP::Platform.windows?
        path = "C:\\Program Files\\test.txt"
        expected = "file:///C:/Program%20Files/test.txt"
      else
        path = "/home/user/my file.txt"
        expected = "file:///home/user/my%20file.txt"
      end

      result = LSP::URIUtils.path_to_uri(path)
      result.should eq(expected)
    end
  end

  describe ".uri_to_path" do
    it "converts URIs back to paths correctly" do
      if LSP::Platform.windows?
        uri = "file:///C:/Users/test/file.txt"
        expected = "C:\\Users\\test\\file.txt"
      else
        uri = "file:///home/user/file.txt"
        expected = "/home/user/file.txt"
      end

      result = LSP::URIUtils.uri_to_path(uri)
      result.should eq(expected)
    end

    it "handles URIs with encoded spaces" do
      if LSP::Platform.windows?
        uri = "file:///C:/Program%20Files/test.txt"
        expected = "C:\\Program Files\\test.txt"
      else
        uri = "file:///home/user/my%20file.txt"
        expected = "/home/user/my file.txt"
      end

      result = LSP::URIUtils.uri_to_path(uri)
      result.should eq(expected)
    end
  end

  describe ".normalize_uri" do
    it "normalizes URI correctly" do
      if LSP::Platform.windows?
        uri = "file:///C:\\Users\\test\\file.txt"
        expected = "file:///C:/Users/test/file.txt"
      else
        uri = "file:///home/user/../user/file.txt"
        expected = "file:///home/user/file.txt"
      end

      result = LSP::URIUtils.normalize_uri(uri)
      result.should eq(expected)
    end
  end

  describe ".dirname_uri" do
    it "gets directory URI correctly" do
      if LSP::Platform.windows?
        uri = "file:///C:/Users/test/file.txt"
        expected = "file:///C:/Users/test"
      else
        uri = "file:///home/user/file.txt"
        expected = "file:///home/user"
      end

      result = LSP::URIUtils.dirname_uri(uri)
      result.should eq(expected)
    end
  end

  describe ".basename_uri" do
    it "gets filename from URI correctly" do
      if LSP::Platform.windows?
        uri = "file:///C:/Users/test/file.txt"
        expected = "file.txt"
      else
        uri = "file:///home/user/file.txt"
        expected = "file.txt"
      end

      result = LSP::URIUtils.basename_uri(uri)
      result.should eq(expected)
    end
  end

  describe ".join_uri" do
    it "joins URI parts correctly" do
      if LSP::Platform.windows?
        base = "file:///C:/Users/test"
        relative = "subfolder/file.txt"
        expected = "file:///C:/Users/test/subfolder/file.txt"
      else
        base = "file:///home/user"
        relative = "subfolder/file.txt"
        expected = "file:///home/user/subfolder/file.txt"
      end

      result = LSP::URIUtils.join_uri(base, relative)
      result.should eq(expected)
    end
  end

  describe ".relative_uri" do
    it "calculates relative URI correctly" do
      if LSP::Platform.windows?
        from = "file:///C:/Users/test"
        to = "file:///C:/Users/test/subfolder/file.txt"
        expected = "subfolder/file.txt"
      else
        from = "file:///home/user"
        to = "file:///home/user/subfolder/file.txt"
        expected = "subfolder/file.txt"
      end

      result = LSP::URIUtils.relative_uri(from, to)
      result.should eq(expected)
    end
  end

  describe ".uris_equal?" do
    it "compares URIs correctly" do
      uri1 = "file:///test/file.txt"
      uri2 = "file:///test/file.txt"
      uri3 = "file:///test/other.txt"

      LSP::URIUtils.uris_equal?(uri1, uri2).should be_true
      LSP::URIUtils.uris_equal?(uri1, uri3).should be_false
    end

    it "handles case sensitivity correctly" do
      if LSP::Platform.windows?
        # Windows should be case insensitive
        uri1 = "file:///C:/Test/File.txt"
        uri2 = "file:///c:/test/file.txt"
        LSP::URIUtils.uris_equal?(uri1, uri2).should be_true
      else
        # Unix should be case sensitive
        uri1 = "file:///home/Test/File.txt"
        uri2 = "file:///home/test/file.txt"
        LSP::URIUtils.uris_equal?(uri1, uri2).should be_false
      end
    end
  end
end
