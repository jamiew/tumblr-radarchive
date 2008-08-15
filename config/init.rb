# Move this to application.rb if you want it to be reloadable in dev mode.
# Merb::Router.prepare do |r|
#   r.match('/').to(:controller => 'foo', :action =>'index')
#   r.default_routes
# end

require 'rubygems'
require 'active_record'
require 'merb_helpers'
require 'models'

# doing this ourselves with config/database.rb
use_orm :activerecord

Merb::Config.use { |c|
  c[:environment]         = 'production',
  c[:framework]           = {},
  c[:log_level]           = 'debug',
  c[:use_mutex]           = false,
  c[:session_store]       = '',
  # c[:session_store]       = 'cookie',
  # c[:session_id_key]      = '_session_id',
  # c[:session_secret_key]  = '265b343634487f9cb543bfd59a7049e769172f84',
  c[:exception_details]   = true,
  c[:reload_classes]      = true,
  c[:reload_time]         = 0.5
}


# Merb::BootLoader.after_app_loads do |app|
#   Merb.add_mime_type(:rss, :to_rss, %w[application/rss+xml], :Encoding => "UTF-8")   
# end
