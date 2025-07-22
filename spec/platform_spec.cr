require "./spec_helper"
require "../src/platform"

describe LSP::Platform do
  describe ".windows?" do
    it "detects platform correctly" do
      {% if flag?(:win32) %}
        LSP::Platform.windows?.should be_true
        LSP::Platform.unix?.should be_false
      {% else %}
        LSP::Platform.windows?.should be_false
        LSP::Platform.unix?.should be_true
      {% end %}
    end
  end

  describe ".line_ending" do
    it "returns correct line ending for platform" do
      {% if flag?(:win32) %}
        LSP::Platform.line_ending.should eq("\r\n")
      {% else %}
        LSP::Platform.line_ending.should eq("\n")
      {% end %}
    end
  end

  describe ".normalize_path" do
    it "normalizes Windows paths correctly" do
      {% if flag?(:win32) %}
        LSP::Platform.normalize_path("C:/Users/test").should eq("C:\\Users\\test")
        LSP::Platform.normalize_path("C:\\Users\\test").should eq("C:\\Users\\test")
        LSP::Platform.normalize_path("\\\\server\\share").should eq("\\\\server\\share")
      {% else %}
        LSP::Platform.normalize_path("C:\\Users\\test").should eq("C:/Users/test")
        LSP::Platform.normalize_path("/home/user").should eq("/home/user")
      {% end %}
    end

    it "handles file:// URIs properly" do
      uri = "file:///C:/Users/test/file.txt"
      LSP::Platform.normalize_path(uri).should eq(uri)
    end
  end

  describe ".absolute_path?" do
    it "detects absolute paths correctly" do
      {% if flag?(:win32) %}
        LSP::Platform.absolute_path?("C:\\Users").should be_true
        LSP::Platform.absolute_path?("\\\\server\\share").should be_true
        LSP::Platform.absolute_path?("relative\\path").should be_false
      {% else %}
        LSP::Platform.absolute_path?("/home/user").should be_true
        LSP::Platform.absolute_path?("relative/path").should be_false
      {% end %}
    end
  end

  describe ".paths_equal?" do
    it "compares paths correctly for platform" do
      {% if flag?(:win32) %}
        # Windows is case-insensitive
        LSP::Platform.paths_equal?("C:\\Users\\Test", "c:\\users\\test").should be_true
        LSP::Platform.paths_equal?("C:/Users/Test", "C:\\Users\\Test").should be_true
      {% else %}
        # Unix is case-sensitive
        LSP::Platform.paths_equal?("/home/User", "/home/user").should be_false
        LSP::Platform.paths_equal?("/home/user", "/home/user").should be_true
      {% end %}
    end
  end

  describe ".join_path" do
    it "joins paths with correct separator" do
      result = LSP::Platform.join_path("base", "sub", "file.txt")

      {% if flag?(:win32) %}
        result.should eq("base\\sub\\file.txt")
      {% else %}
        result.should eq("base/sub/file.txt")
      {% end %}
    end
  end

  describe ".dirname and .basename" do
    it "extracts directory and filename correctly" do
      {% if flag?(:win32) %}
        path = "C:\\Users\\test\\file.txt"
        LSP::Platform.dirname(path).should eq("C:\\Users\\test")
        LSP::Platform.basename(path).should eq("file.txt")
      {% else %}
        path = "/home/user/file.txt"
        LSP::Platform.dirname(path).should eq("/home/user")
        LSP::Platform.basename(path).should eq("file.txt")
      {% end %}
    end
  end
end
