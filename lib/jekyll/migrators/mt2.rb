# Alternate MovableType exporter
# Originally created by Nick Gerakines (mt.rb),
# Modified by Shigeya Suzuki (mt2.rb).
# open source and publically available under the MIT license.
# Use this module at your own risk.

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
    # 

    # Placement of Entries into Categories
    class Placement
    end
     
    # Representation of category
    class Category
      @@categories = { }
      attr_reader :id, :parent_id, :label, :children
      attr_accessor :parent
      
      def initialize(id, parent_id, label)
        @id = id
        @parent_id = parent_id
        @label = label
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
          self.new(cat[:category_id], cat[:category_parent], cat[:category_label])
        end

        self.set_parents
      end
    end

    
    def self.process(dbname, user, pass, host = 'localhost', opts = {})
      FileUtils.mkdir_p "_posts"
      db = Sequel.mysql(dbname, :user => user, :password => pass, :host => host, :encoding => 'latin1')

      # First, read-in category hierarchy
      Jekyll::MT2::Category.fetch_category(db, opts)

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
        if opts[:force_encode]
            [:entry_title, :entry_text, :entry_text_more, :fileinfo_url].each do |k|
                post[k].force_encoding("utf-8") if post[k] != nil
            end
        end
        title = post[:entry_title]
        slug = post[:entry_basename].gsub(/_/, '-')
        date = post[:entry_authored_on]
        content = post[:entry_text]
        more_content = post[:entry_text_more]
        entry_convert_breaks = post[:entry_convert_breaks]
        category_id = post[:entry_category_id].to_i
        category = if category_id != 0 then Category.get_category_path(category_id) else nil end
		
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
           'title' => title.to_s,
           'mt_id' => post[:entry_id],
           'permalink' => permalink,
           'category' => category,
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
