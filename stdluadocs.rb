#!/usr/bin/ruby
require "nokogiri"

f_path = "lua_api_documentation.txt"

def write_arg(arg_hash, xml)
	if arg_hash[:second_ident]
		type = arg_hash[:first_ident]
		name = arg_hash[:second_ident]
	else
		name = arg_hash[:first_ident]
		type = name
	end

	optional = arg_hash[:optional]
	default = arg_hash[:default]

	xml.Arg("optional" => optional) do
		xml.Name { xml << name }
		xml.Type do
			parse_type(type || "unknown", xml)
		end
		if optional
			xml.Default { xml << default }
		end
	end
end

def tokenize_args(argslist)
	tokens = []
	cur_str = ""

	if argslist.strip.size == 0
		return tokens
	end

	argslist.each_char.with_index do |c|
		if c == ')'
			break # looks like we got malformed input with multiple parentheses, let's just quit
		end

		if cur_str.size > 0 && [' ', '[', ']', '(', ')', ','].include?(c)
			tokens << { :type => :text, :value => cur_str }
			cur_str = ""
		end

		if c == '[' or c == '('
			tokens << { :type => :open_optional, :value => c }
		elsif c == ']' or c == ')'
			tokens << { :type => :close_optional, :value => c }
		elsif c == ','
			tokens << { :type => :separator, :value => c }
		elsif c == "="
			tokens << { :type => :equals, :value => c }
		elsif c != ' '
			cur_str += c
		end
	end

	if cur_str.size > 0
		tokens << { :type => :text, :value => cur_str }
	end

	tokens << { :type => :separator, :value => '\0'}

	tokens
end

def parse_args(argslist, xml)
	tokens = tokenize_args(argslist)
	args = []

	cur_arg = {
		:first_ident => nil,
		:second_ident => nil,
		:optional => false,
		:default => nil
	}
	step = :type_or_name
	in_optional = false

	tokens.each_with_index do |tok, i|
		if tok[:type] == :separator then
			write_arg(cur_arg, xml)
			step = :type_or_name
			cur_arg = {
				:first_ident => nil,
				:second_ident => nil,
				:optional => false,
				:default => nil
			}
			next
		end

		if tok[:type] == :open_optional
			in_optional = true
			next
		elsif tok[:type] == :close_optional
			in_optional = false
			next
		end

		if in_optional
			cur_arg[:optional] = true
			if tok[:type] == :text && tok[:value] == "optional"
				next
			end
		end

		case step
		when :type_or_name
			cur_arg[:first_ident] = tok[:value]
			step = :name
		when :name
			if tok[:type] == :equals
				step = :default
			else
				cur_arg[:second_ident] = tok[:value]
				step = :default
			end
		when :default
			next if tok[:type] == :equals
			cur_arg[:optional] = true
			cur_arg[:default] = tok[:value]
			step = :next
		end
	end
end

def parse_type(type, xml)
	# real_type:
	# - unknown
	# - int
	# - number
	# - string
	# - bool
	# - mixed
	# - table
	# - nil

	# purpose:
	# - unknown
	# - x_coord
	# - y_coord
	# - entity_id
	# - component_id
	# - normalfound
	# - normal_x
	# - normal_y
	# - approximate_distance_from_surface

	real_type = :unknown
	purpose = :unknown
	table_type = false
	table_key_type = nil

	if type.start_with? "{" then
		table_type = true
		type = type[1..-1]
		table_key_type = :int
	end

	case type
	when "x", "pos_x"
		real_type = :number
		purpose = :pos_x
	when "y", "pos_y"
		real_type = :number
		purpose = :pos_y
	when "entity_id"
		real_type = :int
		purpose = :entity_id
	when "component_id"
		real_type = :int
		purpose = :component_id
	when "int"
		real_type = :int
	when "number"
		real_type = :number
	when "string"
		real_type = :string
	when "string (comma separated)"
		real_type = :string
		purpose = :csv
	when "multiple return types", "multiple types"
		real_type = :mixed
	when "bool"
		real_type = :bool
	when "nil"
		real_type = :nil
	when "found_normal"
		real_type = :bool
		purpose = :normal_found
	when "normal_x"
		real_type = :number
		purpose = :normal_x
	when "normal_y"
		real_type = :number
		purpose = :normal_y
	when "approximate_distance_from_surface"
		real_type = :number
		purpose = :normal_approximate_distance_from_surface

	# these are used in arguments only
	when "filename"
		real_type = :string
		purpose = :file_name
	when "entity_filename"
		real_type = :string
		purpose = :file_name
	when "variable_name"
		real_type = :string
		purpose = :variable_name
	when "name"
		real_type = :string
		purpose = :name
	when "component_type_name"
		real_type = :string
		purpose = :component_type_name
	when "table_of_component_values"
		table_type = true
		table_key_type = :string
		real_type = :mixed
		purpose = :table_of_component_values
	when "tag", "entity_tag"
		real_type = :string
		purpose = :tag
	when "rotation"
		real_type = :number
		purpose = :rotation
	when "scale_x"
		real_type = :number
		purpose = :scale_x
	when "scale_y"
		real_type = :number
		purpose = :scale_y
	when "parent_id", "child_id"
		real_type = :int
		purpose = :entity_id
	when "enabled", "is_enabled"
		real_type = :bool
		purpose = :enabled
	end

	if table_type
		xml.TableType do
			xml.KeyType { xml << table_key_type.to_s }
			xml.ValueType { xml << real_type.to_s }
			xml.Purpose { xml << purpose.to_s }
		end
	else
		xml.Type do
			xml.Name { xml << real_type.to_s }
			xml.Purpose { xml << purpose.to_s }
		end
	end
end

def parse_type_union(type, xml)
	type_names = []

	if type.include? "|" then
		type_names = type.strip.split("|")
	else
		type_names << type.strip
	end

	xml.TypeUnion do
		type_names.each do |name|
			parse_type(name, xml)
		end
	end
end

def parse_func(func_line, xml)
	func_name = ""
	func_line.each_char do |c|
		break if c == "("
		func_name += c
	end

	return_type_raw = ""
	step = 0
	func_line.each_char do |c|
		return_type_raw += c if step >= 2
		step += 1 if c == '-'
		step += 1 if step == 1 && c == '>'
	end
	step = 0	
	return_type_raw.strip!

	return_types = []

	if return_type_raw.size > 0
		if return_type_raw.include? "," then
			return_types = return_type_raw.split(",")
		else
			return_types = [return_type_raw]
		end
	end

	argslist_start_idx = func_line.index('(')
	argslist_end_idx = func_line.rindex(')')

	if !argslist_end_idx
		argslist_end_idx = func_line.size - 1
	end

	argslist = func_line[(argslist_start_idx+1)..(argslist_end_idx - 1)]

	xml.Function("returns" => return_type_raw.size > 0) do
		xml.Name do xml << func_name end
		parse_args(argslist, xml)
		xml.ReturnTypes {
			return_types.each do |return_type|
				parse_type_union(return_type, xml) if return_type_raw.size > 0
			end
		}
	end
end

builder = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
	xml.Functions do
		File.readlines(f_path).each do |func_line|
			parse_func(func_line.strip, xml)
		end
	end
end

puts builder.to_xml