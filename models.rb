
# a video, image, quote etc
class Post < ActiveRecord::Base
  belongs_to :user
  # has_many :tags
  def self.inheritance_column; :inherit_from; end
  validates_presence_of :type, :on => :create, :message => "can't be blank"
  validates_presence_of :content, :on => :create, :message => "can't be blank"
  validates_presence_of :user_id, :on => :create, :message => "can't be blank"
  validates_uniqueness_of :content, :on => :create, :message => "must be unique" # FIXME TODO is this slow as balls?
  
  def tagged
    # TODO find things that have been tagged relatively frequently
  end
  
  def self.search(terms)
    find_by_sql(["SELECT t.* FROM posts t WHERE #{ (["(lower(t.content) LIKE ? )"] * tokens.size).join(" and ") } ORDER BY s.created_on DESC", tokens])
  end
  
end

# person who posts such nonsense
class User < ActiveRecord::Base
  has_many :posts
  #validates_presence_of :name, :on => :create, :message => "can't be blank"
  validates_presence_of :url, :on => :create, :message => "can't be blank"
  validates_uniqueness_of :url, :on => :create, :message => "must be unique"
  
  def link
    '<a href="'+url+'">'+name+'</a>'
  end

  def self.search(terms)
    find_by_sql(["SELECT t.* FROM users t WHERE #{ (["(lower(t.name.to_s+" "+t.url.to_s) LIKE ? )"] * tokens.size).join(" and ") } ORDER BY s.created_on DESC", tokens])
  end

end

class Tag < ActiveRecord::Base
  belongs_to :post
  validates_presence_of :tag, :on => :create, :message => "can't be blank"  
  validates_presence_of :post_id, :on => :create, :message => "can't be blank"
  validates_presence_of :ip, :on => :create, :message => "can't be blank"
end
