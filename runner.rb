#
# @name   tumblr radar scraper
# @author Jamie Wilkinson <http://jamiedubs.com>
# @email  jamie@internetfamo.us
#
require 'rubygems'
require 'mechanize'
require 'yaml'
require 'active_record'
require 'models'

# Tumblr config
($config ||= {})[:tumblr] = YAML.load_file(File.dirname(__FILE__)+"/config/tumblr.yml")[:tumblr]

# Connect to database
$config[:database] = YAML.load_file( File.dirname(__FILE__)+'/config/database.yml')
ActiveRecord::Base.logger = Logger.new('../database.log')
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
def save(posts)

  added, skipped = 0, 0
  posts.each { |post|  

    # deduce the post type via class
    author, data = {}, {}    
    data[:type] = /\s(.*)_post\s?/.match( post.attributes['class'] )[1].to_s rescue 'photo' # should default to :default

    case data[:type] 
    when 'photo'
      author[:name] = post['href'].split('/')[2].gsub('.tumblr.com','')
      author[:url] = post.attributes['href'].gsub(/post.*$/,'')
      data[:url] = post.attributes['href'] #FIXME? or parse later. hard to tell which user they are...

      # data[:content] = post.search('img')[0].to_s

      unless Post.exists?(:type => 'photo', :url => data[:url])
        # fetch the post's page to get the full details
        puts "Paying a visit to: #{data[:url]}"
        page = $agent.get(data[:url]) rescue (puts "Failed to get second visit: #{$!}"; next)

        # try a few variations on what their content div might be called... sheesh
        photo_divs = ['.post_container','.photo', '.post']
        photo_div = '' #FIXME this is an ugly loop
        photo_divs.each { |div|
         photo_div = div if photo_div.empty? && !page.search("#{div} img").empty? #fingers crossed
        }
        # puts "Settled on photo_div = #{photo_div}"

        # find image and "source" (description)
        data[:content] = page.search(photo_div+' img')[0].to_s rescue nil # first image? TODO find the biggest image
        data[:content] += page.search(photo_div+' .source')[0].to_s rescue "" # next is usually description, right?
        
        # lastly, find reblog link if we're authenticated
        if authenticate?
          src = (page/'iframe')[0]['src']
          raise "No iframe src" if src.nil? or src.empty?
          puts "Fetching iframe page: #{src}"
          page = $agent.get(src)
          first_link = (page/'a:first').remove # a la non-photo post parsing
          data[:reblog_link] = first_link[0]['href']
          puts "reblog link = #{data[:reblog_link].inspect}"          
        end
      end      

    #when 'quote'
    #when 'video' # TODO make request for YouTube stats
    else
      
      # capture reblog link if we're authenticating
      # FIXME this is very loosely targetted and prone to breaking
      if authenticate?
        first_link = post.search('a:first').remove
        data[:reblog_link] = first_link[0]['href']
        # puts "reblog link = #{data[:reblog_link].inspect}" 
      end
      
      # capture the rest of the content & metadata
      link = post.search('.attribution').remove.search('a')[0]
      author[:name] = link.innerHTML
      author[:url] = link['href'].gsub(/\/post.*$/,'')

      # there's only sometimes a permalink, lame. TODO
      link = post.search('a.more')[0]
      data[:url] = link['href'] unless (link.nil? || (link['href'] == author[:url]))
      data[:url] ||= post.search('a')[0]['href'] rescue nil

      #TODO parse into a proper hash a la tumblr? now is the time if we want to at all
      data[:content] = post.innerHTML.strip
      #puts "content = #{data[:content].inspect}"
    end

    # save
    user = User.find_or_initialize_by_url(author)
    user.save! if user.new_record?
    data[:user_id] = user.id
  
    #puts "#{data[:user_id]} #{data[:type]} #{data[:url]} userURL = #{author[:url]}"
    obj = Post.find_or_initialize_by_type_and_user_id_and_url(data)
    if obj.new_record?
      # next if obj.reblog_link.nil? or obj.reblog_link.empty?
      obj.content = data[:content]
      obj.save! rescue (puts "(!!) Failed to save: #{$!}")
      puts "#{data[:type]} by #{author[:name]} @ #{author[:url]}, url = #{data[:url]}"
      post_to_tumblr(obj) rescue (puts "Could not post to tumblr: #{$!}")
      added += 1
    else
      skipped += 1
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
  #puts channel.value
  channel.value = channel.options.select { |o|
    o.value if o.text.strip.downcase == $config[:tumblr][:group_name].strip.downcase
  }
  #puts channel.value
  # TODO do some error checking that we got a value at all if using groups
  # so we're not posting to yr main tumblr

  puts "Submitting reblog..."
  # "ReBlog post" button is a <button> tag, not an <input>
  # appears Mechanize does not know/care about the difference, PATCHME TODO
  # fortunately the form will submit just fine w/o a specific buttton
  # page = $agent.submit(form, form.buttons.first )
  page = $agent.submit(form) rescue (puts "Error submitting form: #{$!}")

  puts "Done. #{page.body.length} bytes on resulting page."

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
  # TODO rescue if couldn't get a page 
  # that requires auth right. Then try...
  begin
    puts "Loading cookies..."
    $agent.cookie_jar.load('cookies.yml')

    # test if we're logged in OK by number of links on an unlogged-in-page
    # FIXME. use some kind of auth header perhaps, or the Tumblr API
    links = $agent.get('http://www.tumblr.com/dashboard').links
    puts "Num of links on dashboard: #{links.length}"
    if links.length <= 13
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
page = $agent.get("http://www.tumblr.com/")
puts "Main... "
save $agent.page.search('li.radar_item').reverse # main
puts "Photos... "
save $agent.page.search('#photos a').reverse # photos

## write to disk
# destination = "tumblr-dashboard-rss.xml"
# File.open(destination,"w") { |f|
#   f.write(content)
# }


