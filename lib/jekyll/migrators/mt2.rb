# Alternate MovableType exporter
# Originally created by Nick Gerakines (mt.rb),
# Modified by Shigeya Suzuki (mt2.rb).
# open source and publically available under the MIT license.
# Use this module at your own risk.

# This script only work with Ruby 1.9.x

raise "This script don't work with Ruby #{RUBY_VERSION}" if RUBY_VERSION < "1.9"

Encoding.default_external = "UTF-8"


require 'rubygems'
require 'sequel'
require 'fileutils'
require 'yaml'

require 'awesome_print'

# NOTE: This converter requires Sequel and the MySQL gems.
# The MySQL gem can be difficult to install on OS X. Once you have MySQL
# installed, running the following commands should work:
# $ sudo gem install sequel
# $ sudo gem install mysql -- --with-mysql-config=/usr/local/mysql/bin/mysql_config

# To export from MovableType database, run following in a directory.
# ruby -rubygems -e 'require "jekyll/migrators/mt";
#                    Jekyll::MT2.process(DB_NAME, DB_USER, DB_PASSWORD, DB_HOST, OPTIONS)'
# 
# Give options as a hash like this:
#   { :force_encode=> true, :permalink_remove_regexp => "\/blog\/"}
#
# Options:
#  encoding                 encoding given to MySQL (default: utf8)
#  force_encode             force encoding of a string retrieved from DB (default: nil)
#  permalink_remove_regexp  regular expression to specify part of permalink to be removed
#

module Jekyll
  module MT2
    # Representation of category
    class Category
      @@categories = { }
      attr_reader :id, :parent_id, :label, :children
      attr_accessor :parent
      
      def initialize(id, parent_id, label, opts)
        @id = id
        @parent_id = parent_id
        @label = if opts[:force_encoding] != nil then
                        label.force_encoding(opts[:force_encoding])
                        else label end
        @parent = nil
        @children = []
        @@categories[@id] = self
      end
      
      def add_child(child)
        @children.push(child)
      end
      
      def set_parent
	    if @parent_id != 0
          @parent = @@categories[@parent_id] 
          @parent.add_child(self)
        end
      end
      
      def self.set_parents
      	@@categories.each {|cid, c| c.set_parent }
      end
      
      def self.categories
        @@categories
      end      

      def self.root_categories
        @@categories
      end
      
      def category_path
      	label
      end
      
      def to_s(n = 0)
        s = (" " * n ) + "#{@label}(#{@id}/#{@parent_id})"
        
        s += "[\n" +
             (" " * (n+2) ) + @children.map{|c| c.to_s(n+2)}.join("\n") + "\n" +
             (" " * n ) + "]" if @children.size != 0
        s
      end
      
      def self.to_s
        @@categories.select {|cid, c| c.parent == nil }.map {|cid, c| c.to_s} .join("\n")
      end
      
      def self.get_category_path(n)
        @@categories[n].category_path
      end
      
      def self.fetch_category(db, opts)
        category_query = "SELECT category_id, category_parent, category_label FROM mt_category"
        category_query += "where category_blog_id = #{opts[:blog_id]}" if opts[:blog_id] != nil
        
        db[category_query].each do |cat|
          self.new(cat[:category_id], cat[:category_parent], cat[:category_label], opts)
        end

        self.set_parents
      end
    end

    # Placement of Entries into Categories
    class Placement
      attr_reader :entry_id, :blog_id
      @@placement = {}

      def initialize(entry_id, blog_id)
        @entry_id = entry_id
        @blog_id = blog_id
        @primary = nil
        @categories = []
      end

      def add(category_id, is_primary)
        @categories.push(category_id)
        @primary = category_id if is_primary
      end

      def self.fetch_placements(db, opts)
        placement_query = "SELECT placement_entry_id, placement_blog_id,
                                  placement_category_id, placement_is_primary FROM mt_placement"
        placement_query += "where placement_blog_id = #{opts[:blog_id]}" if opts[:blog_id] != nil

        db[placement_query].each do |p|
          pp = @@placement[p[:placement_entry_id].to_i] ||=
                     self.new(p[:placement_entry_id], p[:placement_blog_id])
          pp.add(p[:placement_category_id].to_i, p[:placement_is_primary] == 1)
        end
      end

      def categories
        @categories.map {|n| Category.get_category_path(n) }
      end

      def self.get_categories(entry_id)
        if (c = @@placement[entry_id]) != nil
          c.categories
        else
          [ ]
        end
      end
    end
    
    # relationship of object (actually, entry) and tags
    class Tag
      @@tags = { }
      attr_reader :id, :label
      attr_accessor :noramlized
      
      def initialize(id, normalize_id, label, opts)
        @id = id
        @normalize_id = id
        @label = if opts[:force_encoding] != nil then
                        label.force_encoding(opts[:force_encoding])
                        else label end
        @@tags[@id] = self
      end
      
      def self.get_tag_name(n)
        @@tags[n].label
      end
      
      def self.fetch_tags(db, opts)
        tag_query = "SELECT tag_id, tag_is_private, tag_n8d_id, tag_name from mt_tag"
        
        db[tag_query].each do |tag|
          self.new(tag[:tag_id], tag[:tag_n8d_id], tag[:tag_name], opts)
        end
      end

    end
    
    class ObjectTag
      attr_reader :entry_id, :blog_id
      @@object_tags = {}

      def initialize(entry_id, blog_id)
        @entry_id = entry_id
        @blog_id = blog_id
        @tags = []
      end

      def add(tag_id)
        @tags.push(tag_id)
      end

      def self.fetch_object_tags(db, opts)
        tag_query = "SELECT objecttag_id, objecttag_blog_id, objecttag_object_id, objecttag_tag_id
                     FROM mt_objecttag
                     WHERE objecttag_object_datasource = 'entry'"
        tag_query += "and objecttag_blog_id = #{opts[:blog_id]}" if opts[:blog_id] != nil

        db[tag_query].each do |t|
          tt = @@object_tags[t[:objecttag_object_id].to_i] ||=
                     self.new(t[:objecttag_object_id], t[:objecttag_blog_id])
          tt.add(t[:objecttag_tag_id].to_i)
        end        
      end

      def tags
        @tags.map {|n| Tag.get_tag_name(n) }
      end

      def self.get_tags(entry_id)
        if (o = @@object_tags[entry_id]) != nil
          o.tags
        else
          [ ]
        end
      end
    end
    
    def self.process(dbname, user, pass, host = 'localhost', opts = {})
      opts = {
          :encoding => "utf8",
        }.merge(opts)

      FileUtils.mkdir_p "_posts"
      db = Sequel.mysql(dbname, :user => user, :password => pass, :host => host, :encoding => opts[:encoding])

      # First, read-in category hierarchy and placements
      Jekyll::MT2::Category.fetch_category(db, opts)
      Jekyll::MT2::Placement.fetch_placements(db, opts)
      Jekyll::MT2::Tag.fetch_tags(db, opts)
      Jekyll::MT2::ObjectTag.fetch_object_tags(db, opts)

      entry_query = "SELECT entry_id, \
                    entry_basename, \
                    entry_text, \
                    entry_text_more, \
                    entry_authored_on, \
                    entry_title, \
                    entry_convert_breaks, \
                    entry_category_id, \
                    fileinfo_url \
             FROM mt_entry, mt_fileinfo where entry_id = fileinfo_entry_id"

      entry_query += ", blog_id = #{opts[:blog_id]}" if opts[:blog_id] != nil

      

      db[entry_query].each do |post|
        if opts[:force_encoding] != nil
            [:entry_title, :entry_text, :entry_text_more, :fileinfo_url].each do |k|
                post[k].force_encoding(opts[:force_encoding]) if post[k] != nil
            end
        end
        title = post[:entry_title]
        slug = post[:entry_basename].gsub(/_/, '-')
        date = post[:entry_authored_on]
        content = post[:entry_text]
        more_content = post[:entry_text_more]
        entry_convert_breaks = post[:entry_convert_breaks]
        categories = Placement.get_categories(post[:entry_id])
		tags = ObjectTag.get_tags(post[:entry_id])

        # Be sure to include the body and extended body.
        if more_content != nil
          content = content + " \n" + more_content
        end

        # Ideally, this script would determine the post format (markdown,
        # html, etc) and create files with proper extensions. At this point
        # it just assumes that markdown will be acceptable.
        name = [date.year, date.month, date.day, slug].join('-') + '.' +
               self.suffix(entry_convert_breaks)
        
        permalink = post[:fileinfo_url]
        permalink.sub!(/#{opts[:permalink_remove_regexp]}/, '') if opts[:permalink_remove_regexp]
        data = {
           'layout' => 'post',
           'title' => title,
           'mt_id' => post[:entry_id],
           'permalink' => permalink,
           'category' => categories,
           'tags' => tags,
           'date' => date
        }.delete_if { |k,v| v.nil? || v == '' }.to_yaml
        
        File.open("_posts/#{name}", "w") do |f|
          f.puts data
          f.puts "---"
          f.puts content
        end
      end
    end

    def self.suffix(entry_type)
      if entry_type.nil? || entry_type.include?("markdown")
        # The markdown plugin I have saves this as
        # "markdown_with_smarty_pants", so I just look for "markdown".
        "markdown"
      elsif entry_type.include?("textile")
        # This is saved as "textile_2" on my installation of MT 5.1.
        "textile"
      elsif entry_type == "0" || entry_type.include?("richtext")
        # Richtext looks to me like it's saved as HTML, so I include it here.
        "html"
      else
        # Other values might need custom work.
        entry_type
      end
    end
  end
end
