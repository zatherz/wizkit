#!/usr/bin/ruby
require "nokogiri"

CHILD_EXCLUDE = [
	"text",
	"comment",
	"Base",
	"Entity",
	"_Transform"
]

data_dir = ARGV[0]
if !data_dir
	raise "Missing data dir arg"
end


def grab_from_dir(path, components)
	Dir.foreach(path) do |name|
		next if name == "." or name == ".."
		fullpath = File.join(path, name)

		if File.file?(fullpath)
			if name.end_with?(".xml")
				doc = Nokogiri::XML.parse(File.read(fullpath))
				next if doc.children.size == 0
				root_type = doc.children[0].name
				next if root_type != "Entity"

				STDERR.puts "Grabbing from: #{fullpath}"
				ent = doc.children[0]

				ent.children.each do |child|
					name = child.name
					next if CHILD_EXCLUDE.include?(name)
					if components.include?(name)
						STDERR.puts "*#{child.name}"
					else 
						STDERR.puts "+#{child.name}"
						components << name
					end
				end
			end
		else
			STDERR.puts "Entering dir: #{fullpath}"
			grab_from_dir(fullpath, components)
		end
	end

	return components
end

components = grab_from_dir(data_dir, [])
components.sort!

puts components
