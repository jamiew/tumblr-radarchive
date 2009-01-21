
Merb::Router.prepare do |r|
  r.match('/').to(:controller => 'posts', :action => 'index')
  r.match('/page/:page').to(:controller => 'posts', :action => 'index').name(:page)
  r.match('/show/:type/by/:user').to(:controller => 'posts', :action => 'index').name(:show_by)
  r.match('/rss').to(:controller => 'posts', :action => 'index', :format => 'xml').name(:rss)
  r.match('/leaderboard').to(:controller => 'posts', :action => 'leaderboard').name(:leaderboard)
  r.match('/tags').to(:controller => 'posts', :action => 'tags').name(:tags)
  r.match('/tag').to(:controller => 'posts', :action => 'tag').name(:tag)
  # r.default_routes
end


class Posts < Merb::Controller

  def _template_location(action, type = nil, controller = controller_name)
    # puts "controller = #{controller}"
    controller == "layout" ? "layout.#{type}" : "#{action}.#{type}"
  end

  def index
    provides :html, :xml, :rss
    
    @type = (params[:type] || 'everything').gsub(/s$/,'') #ghetto singularize
    @user = params[:user] || 'everyone'
    @limit = 12 # CHANGEME FIXME
    @page = params[:page].to_i > 0 ? params[:page].to_i : 1    
    offset = (@page - 1)*@limit
    
    (conditions ||= []) << 'type = "'+@type.to_s+'"' unless @type == 'everything'
    if @user != 'everyone'
      user = User.find_by_name(@user)
      (conditions ||= []) << 'user_id = "'+user.id.to_s+'"' if user
    end
     
    @posts = Post.find(:all, :include => :user, :conditions => conditions, :order => 'created_at DESC', :limit => @limit, :offset => offset)
    @post_count = Post.count(:id, :conditions => conditions)
    render
  end
  
  def tags
    @tags = Tag.find(:all, :include => { :post => :user })
    # group by type
    # do a graph or some such
    render
  end
  
  def leaderboard
    # @users = User.find(:all)
    @users = User.find_by_sql('SELECT users.name, users.url, count(posts.id) AS post_count FROM posts, users WHERE posts.user_id = users.id GROUP BY users.url')      
    render
  end
  
  def tag_post
    @tag = params[:tag]
    @id = params[:id]
    ip = request.remote_ip
    post = Post.find(@id)
    tag = Tag.find_or_initialize_by_post_id_and_ip(:tag => @tag, :post_id => @id, :ip => ip)
    puts tag.inspect
    if tag.new_record?    
      tag.tag = @tag
      tag.save!
      count = Tag.find_by_tag_and_post_id(tag.tag, tag.post_id).length rescue '0' #FIXME add count_by finders
      return "#{count}"
    else
      puts "Previously #{ip} has voted '#{tag.tag}' on #{@id}, tried to vote #{@tag}"
      return "" # don't tell them anything. let n00bs keep clicking
    end
  end
  
end

class Users < Merb::Controller
  

end
