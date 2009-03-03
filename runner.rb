#!/usr/bin/env ruby
# @name   tumblr radar scraper
# @author Jamie Wilkinson <http://jamiedubs.com>
# @email  jamie@internetfamo.us
#
# 2009-01-28: updated for Tumblr v5, significantly refactored, 
#             and running on Mechanize 0.9 + Nokogiri
# ...
#

require 'rubygems'
# gem 'mechanize', '0.8.5'
gem 'mechanize', '=0.9.0' # w/ Nokogiri (which has no .innerHTML afaik)
require 'mechanize'
require 'yaml'
require 'active_record'
require 'htmlentities'
require 'models'

# Tumblr config
($config ||= {})[:tumblr] = YAML.load_file(File.dirname(__FILE__)+"/config/tumblr.yml")[:tumblr]

# Should we log in first? That way we can get reblog information
def authenticate?; $config[:tumblr][:authenticate] || false; end

# Connect to database
$config[:database] = YAML.load_file( File.dirname(__FILE__)+'/config/database.yml')
#ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__)+'/database.log')
#ActiveRecord::Base.colorize_logging = true
ActiveRecord::Base.establish_connection($config[:database][ (ENV['MERB_ENV'] || :development).to_sym])

# TODO: put in or get from a lib, like extlib, or the future merbified ActiveSupport
class String
  def strip_html(allowed = ['a','img','p','br','i','b','u','ul','li'])
  	str = self.strip || ''
  	str.gsub(/<(\/|\s)*[^(#{allowed.join('|') << '|\/'})][^>]*>/,'')
  end
end

# Tumblr uses Unicode! Otherwise some characters from textareas end up us ?'s
$KCODE = 'UTF-8'


# extend a Mechanize page with methods
# to extract posts from the Tumblr Radar page
class WWW::Mechanize::Page

  def radar_posts  
    # Thanks for adding the post-type to the classes guise! 
    # We'll also grab the post content
    # Author info is no longer available in Tumblr v5
    return self.search('.radar_post').map { |post|  
      type = post['class'].gsub('radar_post','').strip
      { :type => type, :content => post.to_s, :url => post['href'] }
    }
  end
  
end







# transform a Radar post into a Post object and save
def save(data)
    
  tumblelog_url = /(http:\/\/[^\/]*)(\/.*)/.match(data[:url])[1]
  # puts "#{data[:type]}, URL = #{data[:url]}, author = #{tumblelog_url}"
  
  # Find/create the user (tumblelog) who owns this post
  user = User.find_or_initialize_by_url(tumblelog_url)
  user.save! if user.new_record?
  data[:user_id] = user.id
  
  # Create a new object for this post
  # Bail if it already exists in our database (no duplicates please!)
  obj = Post.find_or_initialize_by_user_id_and_url(data)
  return if not obj.new_record?
  obj.content = data[:content]
        
  # Descend to the page and capture reblogging info (if we're logged in & reblogging stuff)
  obj.reblog_link = post_info_for(data[:url])[:reblog_link] if authenticate?
  # puts "> reblog link: #{obj.reblog_link}"
  reblog_post(obj) if authenticate? && !obj.reblog_link.blank?
  obj.save!  
rescue
  puts "(!!) Failed to save or post to Tumblr: #{$!}\n#{$!.backtrace.join("\n\t")}"
  # failed += 1
end


# Fetch a single post and return notable information
# For now just returning the reblog link, but ideally would also grab their Tumblelog's name, etc.
def post_info_for(url)
  puts "post_info_for(#{url})"
  page = $agent.get(url)
  #puts url
  #puts page.search('iframe').select { |i| i['src'] =~ /tumblr\.com/ }.inspect

  iframe_url = page.search('iframe').select { |i| i['src'] =~ /tumblr\.com/ }[0]['src']

  # puts "Getting iframe @ #{iframe_url.inspect}..."
  iframe = $agent.get(iframe_url)
  return { :reblog_link => iframe.links.first.href }

rescue
  STDERR.puts "(!!) Error getting original page: #{$!} \n#{$!.backtrace.join('\n\t')}"
end  



# post to tumblr (by reblogging it to your specified group)
def reblog_post(post)
  puts "> reblogging: #{post.attributes['type']}, #{post.url}, reblog_link => #{post.reblog_link}"
  raise RuntimeError, "Can't post w/o a reblog link" if post.reblog_link.nil? or post.reblog_link.empty? or post.reblog_link == '/'
  
  type = post.attributes['type'] # FIXME: stupid not-overriding-STI hackthrough nonsense
  page = $agent.get("http://www.tumblr.com#{post.reblog_link}")

  # Fill out said form
  # FIXME: having some character encoding issues that end up in ?'s
  # FIXME: find the form more intelligently; sadly both the form id (#edit_post) 
  #   and action (somewhat like the reblog_link) fluctuate a great deal and using index seems more reliable
  form = page.forms[1]
  channel = form.field('channel_id')
  channel.value = channel.options.select { |o|
    o.value if o.text.strip.downcase == $config[:tumblr][:group_name].strip.downcase
  }

  # ....and submit the form
  page = $agent.submit(form)
  # puts "> done; #{page.body.length} bytes on resulting page."
rescue
  STDERR.puts "Error submitting reblog: #{$!}"
end


# Login to Tumblr
# Load cookies, test if we're they're still valid, and authenticate on /login if not
def login(config)

  puts "Loading cookies..."
  $agent.cookie_jar.load('cookies.yml')
  raise RuntimeError, "Cookies no longer valid" unless logged_in?

rescue  
  puts "#{$!}... logging in..."
  page = $agent.get("http://www.tumblr.com/login")
  form = page.form_with(:action => '/login')
  form.email = config[:email]
  form.password = config[:password]
  $agent.submit(form)
  puts "done; saving cookies..."
  $agent.cookie_jar.save_as('cookies.yml') # Save the cookies
end

# Test if we're logged in or not
# Currently checking the number of links on an unlogged-in-page (ghetto)
# Fetching an iframe page would probably be nicer to the servers/Marco
# or could we even use the API authentication-test method?
def logged_in?
  links = $agent.get('http://www.tumblr.com/dashboard').links
  puts "Num of links on dashboard: #{links.length}"

   # Tumblr mainpage has 14 links, which is where we'll get redirected to if not logged in
  return links.length >= 14
end





# main
puts "---------- #{Time.now} ----------"

$agent = WWW::Mechanize.new
$agent.user_agent = 'Radarchive <http://radarchive.tumblr.com>'

# login (so we can get reblog links)
puts "Logging in..."
login($config[:tumblr]) if authenticate? 

# work it
puts "Fetching /radar..."
page = $agent.get("http://www.tumblr.com/radar")
page.radar_posts.reverse.each { |p| save(p) }
puts "Done."

exit 0
