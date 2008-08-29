Radarchive
==============

Merb application that syndicates the Tumblr Radar -- semi-intelligently collects all the posts from it, and can optionally crosspost it to another Tumblr account or group

Adds archives, RSS, a leaderboard, rudimentary tagging and other fun features Marco and David either didn't want or neglected.

Currently in production at http://radarchive.tumblr.com

The Tumblr Radar scraper (runner.rb) is the bulk of the application, and is a well-behaved example of collecting outside of Tumblr's official API. I also have an earlier, much simpler version that generates an RSS feed from your Tumblr dashboard here:
http://github.com/jamiew/tumblr-dashboard-rss

The design is largely copied from Tumblr's Radar itself, with plans to change it 

Made last weekend by Jamie Wilkinson
http://jamiedubs.com

Free Art & Technology Lab
http://fffff.at



Install
============

Edit config/database.yml and load the tables into your database
$ echo database.sql | mysql radarchive_dev

Edit config/tumblr.yml and add your login info if you want to be reblog-cross-posting. Group is your group's URL or unique ID number, and "group name" is required so the scraper can find its name in the list

Run the scraper to get some data. Put this in a cronjob, or a while loop. Be nice and don't scrape at night (EST)... there are no new posts!
$ ruby runner.rb

Start merb and enjoy!
$ merb


