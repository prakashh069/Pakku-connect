require 'xcodeproj'
project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
group = project.main_group.find_subpath('Runner', true)
file_ref = group.new_file('CallPanelController.swift')
target.add_file_references([file_ref])
project.save
