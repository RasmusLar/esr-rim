$:.unshift File.join(File.dirname(__FILE__),"..","lib")
$:.unshift File.join(File.dirname(__FILE__))

require 'minitest/autorun'
require 'rim/git'
require 'rim/dirty_check'
require 'rim/module_info'
require 'rim/sync_module_helper'
require 'test_helper'
require 'fileutils'

include FileUtils

class SyncModuleHelperTest < Minitest::Test
  include TestHelper

  def setup
    test_dir = empty_test_dir("module_sync_helper_test")
    @remote_git_dir = File.join(test_dir, "remote_git")
    FileUtils.mkdir(@remote_git_dir)
    RIM::git_session(@remote_git_dir) do |s|
      s.execute("git init")
      s.execute("git checkout -B testbr")
      write_file(@remote_git_dir, "readme.txt")
      s.execute("git add .")
      s.execute("git commit -m \"Initial commit\"")
    end
    @ws_dir = File.join(test_dir, "ws")
    FileUtils.mkdir(@ws_dir)
    RIM::git_session(@ws_dir) do |s|
      s.execute("git clone #{@remote_git_dir} .")
    end
    @logger = Logger.new($stdout)
  end
  
  def teardown
    remove_test_dirs
  end

  def test_files_are_copied_to_working_dir
    info = RIM::ModuleInfo.new(@remote_git_dir, "test", "testbr")
    cut = RIM::SyncModuleHelper.new(@ws_dir, info, @logger)
    cut.sync
    assert File.exists?(File.join(@ws_dir, "test/readme.txt"))
    assert File.exists?(File.join(@ws_dir, "test/.riminfo"))
  end

  def test_files_of_ignore_list_are_not_removed_when_copying
    test_folder = File.join(@ws_dir, "test")
    write_file(test_folder, "file1")
    write_file(test_folder, "file2")
    write_file(File.join(test_folder, "folder"), "file1")
    write_file(File.join(test_folder, "folder"), "file2")
    write_file(File.join(test_folder, "folder2"), "file1")
    info = RIM::ModuleInfo.new(@remote_git_dir, "test", "testbr", "**/file2")
    cut = RIM::SyncModuleHelper.new(@ws_dir, info, @logger)
    cut.sync
    assert File.exists?(File.join(test_folder, "readme.txt"))
    assert File.exists?(File.join(test_folder, ".riminfo"))
    assert !File.exists?(File.join(test_folder, "file1"))
    assert File.exists?(File.join(test_folder, "file2"))
    assert !File.exists?(File.join(test_folder, "folder/file1"))
    assert File.exists?(File.join(test_folder, "folder/file2"))
    assert File.exists?(File.join(test_folder, "folder/file2"))
  end

  def write_file(dir, name)
    FileUtils.mkdir_p(dir)
    File.open(File.join(dir, name), "w") do |f| 
      f.write("Content of #{name}\n") 
    end
  end
  
end
