#
# @name   tumblr radar scraper
# @author Jamie Wilkinson <http://jamiedubs.com>
# @email  jamie@internetfamo.us
#
require 'rubygems'
require 'mechanize'
require 'yaml'
require 'active_record'
require 'htmlentities'
require 'models'

# Tumblr config
($config ||= {})[:tumblr] = YAML.load_file(File.dirname(__FILE__)+"/config/tumblr.yml")[:tumblr]

# Connect to database
$config[:database] = YAML.load_file( File.dirname(__FILE__)+'/config/database.yml')
ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__)+'/database.log')
ActiveRecord::Base.colorize_logging = true
ActiveRecord::Base.establish_connection($config[:database][ (ENV['MERB_ENV'] || :development).to_sym])

# Should we log in first? Can get reblog data that way
def authenticate?; $config[:tumblr][:authenticate] || false; end


# FIXME put or get from a lib or something geeze
class String
  def strip_html(allowed = ['a','img','p','br','i','b','u','ul','li'])
  	str = self.strip || ''
  	str.gsub(/<(\/|\s)*[^(#{allowed.join('|') << '|\/'})][^>]*>/,'')
  end
end


##########
# save a grip of radar posts to the database
# FIXME this is one gigantic function wowsa o_O
def save(posts)0

  added, skipped, failed = 0, 0, 0
  posts.each { |post|  

    # deduce the post type via class
    author, data = {}, {}    

    # meta info
    data[:type] = 'default' #FIXME
    meta = post.search('.info').remove[0]

    # capture the author
    link = meta.search('a.username')[0]
    author[:name] = link.innerHTML
    author[:url] = link['href']

    # capture permalink
    link = meta.search('a.permalink')[0]
    data[:url] = link['href'] unless link.nil?
    data[:url] ||= post.search('a')[0]['href'] rescue nil # 2nd-try

    # content is the rest of it
    data[:content] = post.innerHTML
    
    # puts "Author = #{author.inspect}, URL = #{data[:url]}"
    
    # save
    user = User.find_or_initialize_by_url(author)
    user.save! if user.new_record?
    data[:user_id] = user.id
  
    #puts "#{data[:user_id]} #{data[:type]} #{data[:url]} userURL = #{author[:url]}"
    obj = Post.find_or_initialize_by_user_id_and_url(data)
    if not obj.new_record?
      skipped += 1
      next
    end
      
    # capture reblog URL and re-post if we are authenticating
    if authenticate?
      puts "Getting original page #{data[:url]}..."
      page = $agent.get(data[:url])
      iframe_url = page.search('iframe')[0]['src']        
      
      puts "Getting iframe @ #{iframe_url}..."
      iframe = $agent.get(iframe_url)
      obj.reblog_link = iframe.links.first.href
      puts "reblog link = #{obj.reblog_link.inspect}"
    end

    # save!
    begin
      obj.content = data[:content]
      obj.save!
      puts "#{data[:type]} by #{author[:name]} @ #{author[:url]}, url = #{data[:url]}"
      added += 1
          
      # now post to tumblr if we're authenticated
      if authenticate?
        puts "Posting to tumblr..."
        post_to_tumblr(obj) rescue (puts "Could not post to tumblr: #{$!}")
      end
    rescue
      puts "(!!) Failed to save or post to Tumblr: #{$!}\n#{$!.backtrace.join("\n\t")}"
      failed += 1
    end
  }
  
  puts "#{added} new posts, #{skipped} skipped."

end




#########
# post to tumblr (by reblogging it to your specified group)
def post_to_tumblr(post)
  puts "post to tumblr: #{post.id}, #{post.attributes['type']}, #{post.url}, reblog_link => #{post.reblog_link}"
  
  raise RuntimeError, "Can't post w/o a reblog link" if post.reblog_link.nil? or post.reblog_link.empty? or post.reblog_link == '/'
  
  type = post.attributes['type'] # stupid
  #puts "http://www.tumblr.com#{post.reblog_link}"
  page = $agent.get("http://www.tumblr.com#{post.reblog_link}")
  # puts $agent.submit(page.forms[0])

  #puts "Filling out the form..."
  form = page.forms[0]
  channel = form.field('channel_id')
  channel.value = channel.options.select { |o|
    o.value if o.text.strip.downcase == $config[:tumblr][:group_name].strip.downcase
  }
  # TODO do some error checking that we got a value at all if using groups
  # so we're not posting to yr main tumblr

  # "ReBlog post" button is a <button> tag, not an <input>
  # appears Mechanize does not know/care about the difference, PATCHME TODO
  # fortunately the form will submit just fine w/o a specific buttton
  # page = $agent.submit(form, form.buttons.first )
  puts "Submitting reblog..."
  begin
    page = $agent.submit(form)
    puts "Done. #{page.body.length} bytes on resulting page."
  rescue
    puts "Error submitting form: #{$!}"
  end

end




##########
# init
puts "----------"
puts Time.now

$agent = WWW::Mechanize.new
$agent.user_agent = 'Radarchive <http://radarchive.tumblr.com>'

# log in (so we can get reblog links)
if authenticate? 
  
  # load cookies
  # TODO rescue if couldn't get a page that requires authentication -- right now just checking dashboard
  begin
    puts "Loading cookies..."
    $agent.cookie_jar.load('cookies.yml')

    # test if we're logged in OK by number of links on an unlogged-in-page
    # FIXME. use some kind of auth header perhaps, or the Tumblr API
    links = $agent.get('http://www.tumblr.com/dashboard').links
    puts "Num of links on dashboard: #{links.length}"
    if links.length <= 14 # TODO Tumblr mainpage has 14 links.
      raise RuntimeError, "Could not reach the Dashboard, cookies are probably no longer valid!" 
    end
  rescue  
    puts "#{$!}... logging in..."
    page = $agent.get("http://www.tumblr.com/login")
    form = page.forms[0]
    form.email = $config[:tumblr][:email]
    form.password = $config[:tumblr][:password]
    $agent.submit(form)
    puts "done, saving cookies"
    $agent.cookie_jar.save_as('cookies.yml') # Save the cookies
  ensure
    puts "Authenticated!"
  end
end

# get radar page
page = $agent.get("http://www.tumblr.com/explore")
save $agent.page.search('.radar_item').reverse # main

## write to disk
# destination = "tumblr-dashboard-rss.xml"
# File.open(destination,"w") { |f|
#   f.write(content)
# }


