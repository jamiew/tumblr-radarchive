# @name   tumblr radar scraper
# @author Jamie Wilkinson <http://jamiedubs.com>
# @email  jamie@internetfamo.us

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



# extracts array of posts from a mechanize page
class WWW::Mechanize::Page

  def radar_posts  
    return self.search('.radar_item').map { |post|      
      
      # try our best to guess the post type
      # TODO can determine post-facto via Tumblr API
      if post.search('a.link').length > 0
        type = 'link' 
      elsif post.search('div.quote').length > 0
        type = 'quote'
      elsif post.search('embed').length > 0
        type = 'audio'
      # TODO ...
      else
        type = 'default'
      end
      
      data = { :type => type, :content => post.search('div')[0].innerHTML }      

      # capture permalink
      link = post.search('a.permalink')[0]
      data[:url] = link['href']
      # data[:url] ||= post.search('a')[0]['href'] rescue nil # 2nd-try
    
      # capture the author info
      # meta = post.search('.info').remove[0]
      link = post.search('a.username')[0]      
      data[:author] = { :name => link.innerHTML, :url => link['href'] }
      data
    }
  end

  def radar_images
    return self.search('#photos a').map { |link|
      url = /url\(\'(.*)\'\)/.match(link['style'])[1]
      data = { :type => 'photo', :url => link['href'], :content => '<img src="'+url+'" />' }
      author_url = /\w+([-+.'\/]\w+)*.\w+([-.]\w+)*\.\w+([-.]\w+)*/.match(link['href'])[0] 
      data[:author] = { :name => link['title'], :url => "http://#{author_url}" }
      data
    }
  end
  
end







# save a Radar post as an Post AR object
def save(data)
    
  author = data.delete(:author)    
  puts "URL = #{data[:url]}, Author = #{author.inspect}"
  
  # save
  user = User.find_or_initialize_by_url(author)
  user.save! if user.new_record?
  data[:user_id] = user.id

  #puts "#{data[:user_id]} #{data[:type]} #{data[:url]} userURL = #{author[:url]}"
  obj = Post.find_or_initialize_by_user_id_and_url(data)
  if not obj.new_record?
    # skipped += 1
    # next
    return
  end
      
  # capture reblog URL and re-post if we are authenticating
  if authenticate?
    # puts "Getting original page #{data[:url]}..."
    begin
      page = $agent.get(data[:url])
      iframe_url = page.search('iframe').select { |i| i['src'] =~ /tumblr\.com/ }[0]['src'] rescue nil
    
      # puts "Getting iframe @ #{iframe_url.inspect}..."
      iframe = $agent.get(iframe_url)
      obj.reblog_link = iframe.links.first.href
      puts "reblog link = #{obj.reblog_link.inspect}"
    rescue
      puts "(!!) Error getting original page: #{$!}"
    end
  end
  

  # save!
  begin
    obj.content = data[:content]
    puts "Content length #{data[:content].length}"
    obj.save!
    puts "#{data[:type]} by #{author[:name]} @ #{author[:url]}, url = #{data[:url]}"
    # added += 1
        
    # now post to tumblr if we're authenticated
    if authenticate? && !obj.reblog_link.blank?
      puts "Posting to tumblr..."
      post_to_tumblr(obj) rescue (puts "Could not post to tumblr: #{$!}")
    end
  rescue
    puts "(!!) Failed to save or post to Tumblr: #{$!}"
    # puts "(!!) Failed to save or post to Tumblr: #{$!}\n#{$!.backtrace.join("\n\t")}"
    # failed += 1
  end

  # puts "#{added} new posts, #{skipped} skipped."

end



# post to tumblr (by reblogging it to your specified group)
def post_to_tumblr(post)
  puts "Post to Tumblr: #{post.id}, #{post.attributes['type']}, #{post.url}, reblog_link => #{post.reblog_link}"
  
  raise RuntimeError, "Can't post w/o a reblog link" if post.reblog_link.nil? or post.reblog_link.empty? or post.reblog_link == '/'
  
  type = post.attributes['type'] # FIXME: stupid
  page = $agent.get("http://www.tumblr.com#{post.reblog_link}")

  # fill out the form
  form = page.forms[0]
  channel = form.field('channel_id')
  channel.value = channel.options.select { |o|
    o.value if o.text.strip.downcase == $config[:tumblr][:group_name].strip.downcase
  }

  # TODO do some error checking that we got a value at all if using groups
  # so we're not accidentally posting to yr main tumblr

  puts "Submitting reblog..."
  begin
    page = $agent.submit(form)
    puts "Done. #{page.body.length} bytes on resulting page."
  rescue
    puts "Error submitting reblog: #{$!}"
  end

end




# init
puts "---------- #{Time.now} ----------"

$agent = WWW::Mechanize.new
$agent.user_agent = 'Radarchive <http://radarchive.tumblr.com>'


# log in (so we can get reblog links)
if authenticate? 
  
  # load cookies
  # TODO rescue if couldn't get a page that requires authentication -- right now doing an extra fetch for the dashboard
  begin
    puts "Loading cookies..."
    $agent.cookie_jar.load('cookies.yml')

    # test if we're logged in via the number of links on an unlogged-in-page
    # FIXME. just use some kind of auth header perhaps
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

puts "Images..."
page.radar_images.reverse.each { |p| save(p) }
puts "Posts..."
page.radar_posts.reverse.each  { |p| save(p) }
puts "Done."

exit 0
