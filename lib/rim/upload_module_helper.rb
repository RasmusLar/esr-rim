require 'rim/module_helper'
require 'rim/rim_info'
require 'rim/file_helper'
require 'rim/dirty_check'
require 'rim/status_builder'
require 'tempfile'

module RIM

class UploadModuleHelper < ModuleHelper

  def initialize(workspace_root, module_info, logger)
    super(workspace_root, module_info, logger)
  end

  # do the module uploads for revisions given by sha
  def upload(parent, sha1s)
    upload_module_changes(parent, sha1s)      
  end
  
private

  # upload the content of the module
  def upload_module_changes(parent_sha1, sha1s)
    remote_path = fetch_module
    # search for the first revision that is not 
    tmp_git_path = clone_or_fetch_repository(remote_path, module_tmp_git_path(@remote_path))
    RIM::git_session(tmp_git_path) do |dest|
      local_branch = nil
      remote_branch = nil
      infos = nil
      RIM::git_session(@ws_root) do |src|
        infos = get_branches_and_revision_infos(src, dest, parent_sha1, sha1s)
        if infos.branches.size == 1
          remote_branch = infos.branches[0]
          if dest.has_branch?(remote_branch)
            infos.rev_infos.each do |rev_info|
              local_branch = create_update_branch(dest, infos.parent_sha1, rev_info.src_sha1) if !local_branch
              copy_revision_files(src, rev_info.src_sha1, tmp_git_path, rev_info.rim_info.ignores)
              commit_changes(dest, local_branch, rev_info.src_sha1, rev_info.message)
            end
          else
            raise RimException.new("Module #{@module_info.local_path} is not based on branch. No push can be performed.")
          end
        elsif infos.branches.size > 1
          raise RimException.new("There are commits for module #{@module_info.local_path} on multiple target revisions (#{infos.branches.join(", ")}).")
        end
      end
      # Finally we're done. Push the changes
      if local_branch && dest.rev_sha1(local_branch) != infos.parent_sha1  
        push_branch = @module_info.remote_branch_format && !@module_info.remote_branch_format.empty? \
            ? @module_info.remote_branch_format % remote_branch : remote_branch
        dest.execute("git push #{@remote_url} #{local_branch}:#{push_branch}")
        dest.execute("git checkout --detach #{local_branch}")
        dest.execute("git branch -D #{local_branch}")
        @logger.info("Commited changes for module #{@module_info.local_path} to remote branch #{push_branch}.")
      else
        @logger.info("No changes to module #{@module_info.local_path}.")
      end                              
    end
  end

  # search backwards for all revision infos
  def get_branches_and_revision_infos(src_session, dest_session, parent_sha1, sha1s)
    infos = []
    branches = []
    dest_parent_sha1 = nil
    (sha1s.size() - 1).step(0, -1) do |i|
      info = get_revision_info(src_session, dest_session, sha1s[i])
      if !info.dest_sha1 && info.rim_info.target_revision
        infos.unshift(info)
        branches.push(info.rim_info.target_revision) if !branches.include?(info.rim_info.target_revision)
      else
        dest_parent_sha1 = info.dest_sha1
        break
      end
    end
    dest_parent_sha1 = get_riminfo_for_revision(src_session, parent_sha1).revision_sha1 if !dest_parent_sha1
    dest_parent_sha1 = infos.first.rim_info.revision_sha1 if !dest_parent_sha1 && !infos.empty?
    return Struct.new(:branches, :parent_sha1, :rev_infos).new(branches, dest_parent_sha1, infos)      
  end
  
  RevisionInfo = Struct.new(:dest_sha1, :src_sha1, :rim_info, :message)

  # collect infos for a revision
  def get_revision_info(src_session, dest_session, src_sha1)
    module_status = StatusBuilder.new.rev_module_status(src_session, src_sha1, @module_info.local_path)
    rim_info = get_riminfo_for_revision(src_session, src_sha1)
    dest_sha1 = dest_session.rev_sha1("rim-#{src_sha1}")
    msg = src_session.execute("git show -s --format=%B #{src_sha1}") 
    RevisionInfo.new(module_status && module_status.dirty? ? dest_sha1 : rim_info.revision_sha1, src_sha1, rim_info, msg)
  end
  
  # clone or fetch repository
  def clone_or_fetch_repository(remote_url, local_path)
    FileUtils.mkdir_p local_path
    RIM::git_session(local_path) do |s|
      if !File.exist?(File.join(local_path, ".git"))
        s.execute("git clone #{remote_url} .")
      else
        s.execute("git fetch")
      end
    end
    local_path
  end


  # commit changes to session
  def commit_changes(session, branch, sha1, msg)
    if session.status.lines.any?
      # add before commit because the path can be below a not yet added path
      session.execute("git add --all")
      msg_file = Tempfile.new('message')
      begin
        msg_file << msg
        msg_file.close
        session.execute("git commit -F #{msg_file.path}")
      ensure
        msg_file.close(true)
      end
      # create tag
      session.execute("git tag rim-#{sha1} refs/heads/#{branch}")
    end
  end

  # get target revision for this module for workspace revision
  def get_riminfo_for_revision(session, sha1)
    session.execute("git show #{sha1}:#{File.join(@module_info.local_path, RimInfo::InfoFileName)}") do |out, e|
      return RimInfo.from_s(!e ? out : "")
    end
  end 
  
  # create update branch for given revision
  def create_update_branch(session, dest_sha1, src_sha1)
    branch = "rim/#{src_sha1}" 
    session.execute("git checkout -B #{branch} #{dest_sha1}")
    branch
  end

  # copy files from given source revision into destination dir
  def copy_revision_files(src_session, src_sha1, dest_dir, ignores)
    Dir.mktmpdir do |tmp_dir|
      src_session.execute("git archive --format tar #{src_sha1} #{@module_info.local_path} | tar -x -C #{tmp_dir}")
      tmp_module_dir = File.join(tmp_dir, @module_info.local_path)
      files = FileHelper.find_matching_files(tmp_module_dir, false, "/**/*", File::FNM_DOTMATCH)
      files.delete(".")
      files.delete("..")
      files.delete(RimInfo::InfoFileName)
      files -= FileHelper.find_matching_files(tmp_module_dir, false, ignores)
      # have source files now. Now clear destination folder and copy
      prepare_empty_folder(dest_dir, ".git/**/*")
      files.each do |f|
        src_path = File.join(tmp_module_dir, f)
        if File.file?(src_path)
          path = File.join(dest_dir, f)
          FileUtils.mkdir_p(File.dirname(path))
          FileUtils.cp(src_path, path)
        end        
      end
    end 
  end 

end

end
