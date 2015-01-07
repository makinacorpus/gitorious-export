include FileUtils
require 'json'


def get_output_dir(name)
  File.join(File.dirname(__FILE__), name)
end

def get_project_dir(base, project_name)
  File.join(base, project_name)
end

def get_repo_dir(base, project_name, repo_name)
  File.join(get_project_dir(base, project_name), repo_name)
end

def export_projects_data(projects, output_dir)
  hashed = projects.map do |project|
    repositories = project.repositories.map do |repo|
      commiters = []
      readers = []
      repo.committerships.map do |cm|
        cm.members.map do |member|
          if member.class.name == 'Group'
            member.members.map do |u|
              commiters.push u.login
            end
          else
            commiters.push member.login
          end
        end
      end
      project.content_memberships.map do |m|
        if m.member.class.name == 'User'
          if !commiters.include?(m.member.login)
            readers.push m.member.login
          end
        end
        if m.member.class.name == 'Group'
          m.member.members.map do |u|
            if !commiters.include?(u.login)
              readers.push u.login
            end
          end
        end
        readers.uniq!
        commiters.uniq!
        data = {:name => repo.name,
                :description => repo.description,
                :owner_type => "User",
                :owner_id => "root",
                :readers => readers,
                :commiters => commiters,
                :clone_url => repo.clone_url}
        data
      end
    end

    {:title => project.title,
     :owner_type => "User",
     :owner_id => "root",
     :description => project.description,
     :slug => project.slug,
     :repositories => repositories}
  end

  File.open(File.join(output_dir, 'export.json'), 'w'){|f| f.write(
    JSON.pretty_generate(JSON.parse(hashed.to_json)))}
end

def export_projects_source(projects, output_dir)
  names = projects.map do |p| p.slug end
  to_wipe = Dir.entries(output_dir).select {
    |entry| File.directory? File.join(output_dir, entry) and !(entry =='.' || entry == '..') and !names.include?(entry)
  }
  to_wipe.map do |e|
    e = get_project_dir(output_dir, e)
    puts "  removing stale project: #{e}"
    #rm_rf "#{output_dir}/#{e}"
  end
  projects.each do |project|
    project_dir = get_project_dir(output_dir, project.slug)
    Dir.mkdir(project_dir) if !File.directory?(project_dir)
    puts "#{project.title} cloning #{project.repositories.count}"
    names = project.repositories.map do |p| p.name end
    to_wipe = Dir.entries(project_dir).select {
      |entry| File.directory? File.join(project_dir, entry) and !(entry =='.' || entry == '..') and !names.include?(entry)
    }
    to_wipe.map do |e|
      puts "  removing stale repo: #{project_dir}/#{e}"
      rm_rf "#{project_dir}/#{e}"
    end
    project.repositories.each do |repo|
      project_dir = get_project_dir(output_dir, project.slug)
      Dir.chdir(project_dir) do
        puts "  cloning #{repo.name} (#{repo.full_hashed_path})"
        rp = "/home/gitorious-git/repositories"
        if !File.directory? repo.name
          cmd = "git clone --mirror #{rp}/#{repo.full_hashed_path} #{repo.name}"
          puts cmd
          `#{cmd}`
        else
          push_url = "#{Dir.pwd}/#{repo.name}"
          Dir.chdir("#{rp}/#{repo.full_hashed_path}.git") do
            cmd = "git push --mirror #{push_url}"
            puts cmd
            `#{cmd}`
          end
        end
        empty = Dir.chdir(repo.name) do
          num_refs = `git count-objects | cut -c 1`
          num_refs == '1'
        end
        rm_rf repo.name if empty
      end
    end
  end
end

def export_projects(projects, output_dir)
  export_projects_data(projects, output_dir)
  export_projects_source(projects, output_dir)
end

def export_users(users, output_dir)
  user_hashed = users.map do |user|
    {:login => user.login,
     :email => user.email,
     :fullname => user.fullname,
     :ssh_keys => user.ssh_keys.map{|k| k.key}}
  end

  File.open(File.join(output_dir, 'users.json'), 'w'){|f| f.write(
    JSON.pretty_generate(JSON.parse(user_hashed.to_json)))}
end
output_dir = get_output_dir(File.join('..', 'output'))

Dir.mkdir(output_dir) if !File.directory?(output_dir)
projects = Project.all
export_projects(projects, output_dir)
export_users(User.all, output_dir)
