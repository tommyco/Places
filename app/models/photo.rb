# Encapsulate all information and content access to a photograph
# This model uses GridFS and will be responsible for extracting
# geolocation coordinates from each photo and locating the nearest place
# to where a photo was taken.
class Photo
  include Mongoid::Document

  # Note: place attribute is used to realized a Many-to-One 
  # relationship between Photo and Place.
  # The place attribute holds a BSON::ObjectId id object.
  attr_accessor :id, :location, :place
  attr_writer :contents

  # Returns a MongoDB client from Mongoid referencing
  # the default database from the config/mongoid.yml file
  def self.mongo_client
  	Mongoid::Clients.default
  end

  # Initialize the instance attributes of Photo
  # from the hash returned from queries like
  # mongo_client.database.fs.find
  #
  # Note: a default instance will be created if no hash is present
  def initialize(doc=nil)
  	if (!doc.nil?)
  		@id = doc[:_id].to_s
  		@location = Point.new(doc[:metadata][:location])
  		@place = doc[:metadata][:place]
  	end
  end

  # Returns true if the instance has been created within GridFS
  def persisted?
  	!@id.nil?
  end

  # Helper method to convert string id to BSON::ObjectId type
  def id_object
    BSON::ObjectId.from_string(@id)
  end

  # Store a new instance into GridFS
  def save
  	if !persisted?
  		# extract geolocation information from the jpeg image
  		gps=EXIFR::JPEG.new(@contents).gps

  		# store the content type of image/jpeg in the GridFS contentType file property
  		description={}
  		description[:content_type]="image/jpeg"

  		# store the GeoJSON Point format of the image location in the GridFS metadata file property and the object in class’ location property.
  		@location=Point.new(:lng=>gps.longitude, :lat=>gps.latitude)
  		description[:metadata] = {}
  		description[:metadata][:location]=@location.to_hash
  		description[:metadata][:place]=@place

		  # store the data contents in GridFS
		  # first rewind to the top of the file
		  @contents.rewind
		  grid_file = Mongo::Grid::File.new(@contents.read, description)
		  id=self.class.mongo_client.database.fs.insert_one(grid_file)

		  # store the generated _id for the file in the :id property of the Photo model instance.
		  @id=id.to_s
	  else
      # update the file information of the persisted instance into GridFS
		  doc = self.class.mongo_client.database.fs.find(:_id=>id_object).first
		  doc[:metadata][:location] = @location.to_hash
		  doc[:metadata][:place] = @place
		  self.class.mongo_client.database.fs.find(:_id=>id_object).update_one(doc)
  	end
  end

  # Returns a collection of Photo instances representing each file
  # returned from the database
  def self.all(offset=0, limit=nil) 
  	result = mongo_client.database.fs.find.skip(offset)
  	result = result.limit(limit) if !limit.nil?
  	return result.map { |doc| Photo.new(doc) }
  end

  # Returns an instance of a Photo based on the input id
  def self.find(id)
  	_id = BSON::ObjectId.from_string(id)
  	doc = mongo_client.database.fs.find(:_id=>_id).first
  	return doc.nil? ? nil : Photo.new(doc)
  end

  # Returns the data contents of the file
  def contents
  	doc = self.class.mongo_client.database.fs.find_one(_id:id_object)
  	if doc
  		buffer=""
  		doc.chunks.reduce([]) do |x,chunk|
  			buffer << chunk.data.data
  		end
  		return buffer
  	end
  end

  # Delete the file and content associated with
  # the id of the object instance
  def destroy
  	self.class.mongo_client.database.fs.find(:_id=>id_object).delete_one
  end

  # Returns the _id of the document within the places collection
  # This place document must be within a specified distance threshold
  # of where the photo was taken
  def find_nearest_place_id(max_meters)
  	result = Place.near(@location, max_meters).projection({_id:1})
  	if !result.nil?
  		result = result.limit(1).first
  		return result[:_id]
  	end
  end

  # Custom getter of the place attribute
  # Find and return a Place instance that represents 
  # the stored id property in the file info.
  def place
  	return Place.find(@place.to_s) unless @place.nil?
  end

  # Custom setter of the place attribute
  # Update the place id by accepting a 
  #     BSON::ObjectId, String or a Place instance
  # Derived a BSON::ObjectId from what is passed in
  def place=(new_place_id)
  	case
  	when new_place_id.is_a?(Place)
  		@place = BSON::ObjectId.from_string(new_place_id.id)
  	when new_place_id.is_a?(String)
    	@place = BSON::ObjectId.from_string(new_place_id)  		
  	when new_place_id.is_a?(BSON::ObjectId)
  		@place = new_place_id
  	end
	  doc = self.class.mongo_client.database.fs.find(:_id=>id_object).first
	  doc[:metadata][:place] = @place
  end

  # Accepts the BSON::ObjectId of a Place
  # and returns a collection view of photo documents
  # that have the foreign key reference.
  def self.find_photos_for_place(place_id)
  	case 
  	when place_id.is_a?(String)
  		new_place_id = BSON::ObjectId.from_string(place_id)
  	when place_id.is_a?(BSON::ObjectId)
  		new_place_id = place_id
  	end

  	doc = mongo_client.database.fs.find("metadata.place":new_place_id)
  	return doc
  end
end
