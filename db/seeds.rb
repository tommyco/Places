# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

require 'pp'

# clear GridFS of all files
Photo.all.each { |photo| photo.destroy }

# clear the places collection of all documents
Place.all.each { |place| place.destroy }

# create the 2dsphere index for the nested geometry.geolocation property within the places collection
Place.create_indexes

# populate the places collection from a JSON file
Place.load_all(File.open('./db/places.json'))

# populate GridFS with images located in the db/ folder
Dir.glob("./db/image*.jpg") {|f| photo=Photo.new; photo.contents=File.open(f,'rb'); photo.save}

# for each photo in GridFS, locate the nearest place within 1 mile of each photo
# and associate the photo with that place
Photo.all.each {|photo| place_id=photo.find_nearest_place_id 1*1609.34; photo.place=place_id; photo.save}

# test the seeding
pp Place.all.reject {|pl| pl.photos.empty?}.map {|pl| pl.formatted_address}.sort
