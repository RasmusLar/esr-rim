require 'rim/status_builder'

module RIM
module Command

class Status < Command

  def initialize(opts)
    opts.banner = "Usage: rim status [<options>] [<to-rev>|<from-rev>..<to-rev>]"
    opts.description = "Prints commits and their RIM status"
    opts.separator ""
    opts.separator "Without revision arguments checks the current branch and all local ancestors."
    opts.separator "With a single <to-rev> checks that revision and all local ancestors."
    opts.separator "Otherwise checks <to-rev> and ancestors without <from-rev> and ancestors."
    opts.separator ""
    opts.on("-d", "--detailed", "print detailed status") do
      @detailed = true
    end
    opts.on("--verify-clean", "exit with error code 1 if commits are dirty") do
      @verify_clean = true
    end
  end

  def invoke()
    root = project_git_dir
    rev_arg = ARGV.shift
    stat = nil
    RIM.git_session(root) do |gs|
      sb = RIM::StatusBuilder.new
      if rev_arg
        if rev_arg =~ /\.\./
          from_rev, to_rev = rev_arg.split("..")
        else
          from_rev, to_rev = nil, rev_arg
        end
        stat = sb.rev_history_status(gs, to_rev, :stop_rev => from_rev)
        print_status(gs, stat)
      else
        if gs.uncommited_changes?
          stat = sb.fs_status(root)
          print_status(gs, stat)
        end
        branch = gs.current_branch_name
        stat = sb.rev_history_status(gs, branch)
        print_status(gs, stat)
      end
    end
    if @verify_clean && any_dirty?(stat)
      exit(1)
    end
  end

  private 

  def any_dirty?(stat)
    stat.dirty? || stat.parents.any?{|p| any_dirty?(p)}
  end

  def print_status(gs, stat)
    # don't print the last (remote) status nodes
    # note: this also excludes the initial commit
    return if stat.git_rev && stat.parents.empty?
    dirty_mods = stat.modules.select{|m| m.dirty?}
    stat_info = dirty_mods.empty? ? "[   OK]" : "[DIRTY]"
    headline = ""
    if stat.git_rev
      out = gs.execute "git rev-list --format=oneline -n 1 #{stat.git_rev}" 
      if out =~ /^(\w+) (.*)/
        sha1, comment = $1, $2
        headline += "#{stat_info} #{sha1[0..6]} #{comment}"
      end
    else
      headline += "#{stat_info} ------- uncommitted changes"
    end
    if @detailed
      @logger.info headline
      dirty_mods.each do |m|
        @logger.info "        - #{m.dir}"
      end
    elsif dirty_mods.size > 0
      @logger.info "#{headline} (#{dirty_mods.size} modules dirty)"
    else
      @logger.info headline
    end
    stat.parents.each do |p|
      print_status(gs, p)
    end
  end

end

end
end
