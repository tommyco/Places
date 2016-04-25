# Primary class
# Two supporting classes are Point and AddressComponent
class Place
  include ActiveModel::Model
  include Mongoid::Document

  attr_accessor :id, :address_components, :formatted_address, :location

  # set the attributes from a hash with keys
  # :_id, :address_components, :formatted_address & :geometry.geolocation
  #
  # note:_id is a BSON::ObjectId object
  # note: geolocation is in GeoJSON Point format (obtained from google maps)
  def initialize(params)
    @id=params[:_id].to_s 
    @formatted_address=params[:formatted_address]
    @location=Point.new(params[:geometry][:geolocation])

    # convert the array of addresses into AddressComponent objects
    @address_components = []
    if !params[:address_components].nil?
      params[:address_components].each { |a|
        @address_components << AddressComponent.new(a)
      }
    end
  end

  # Returns true if the model instance has been saved to the database.
  def persisted?
    !@id.nil?
  end
  
  # Helper method to convert string id to BSON::ObjectId type
  def id_object
    BSON::ObjectId.from_string(@id)
  end

  # Returns a MongoDB client from Mongoid referencing the
  # default database from the config/mongoid.yml file
  def self.mongo_client
  	Mongoid::Clients.default
  end

  # Returns a reference to the places collection
  def self.collection
  	self.mongo_client['places']
  end

  # Bulk load a JSON document with places information into
  # the places collection
  def self.load_all(json_data)
  	data = File.read(json_data)
  	collection.insert_many(JSON.parse(data))
  end

  # Return a Mongo::Collection::View with a query
  # to match documents with matching short_name within address_components
  def self.find_by_short_name(name)
    Mongo::Collection::View.new(collection,{:'address_components.short_name'=>name})
  end

  # Helper class that will accept a Mongo::Collection::View 
  # and return a collection of Place instances
  def self.to_places(view_collection)
    view_collection.collect { |aview|
      Place.new(aview)
    }
  end

  # Return an instance of Place for a supplied id
  def self.find(id)
    _id = BSON::ObjectId.from_string(id)
    doc = collection.find(:_id=>_id).first
    Place.new(doc) unless doc.nil?
  end

  # Return an instance of all documents as Place instances
  def self.all(offset=0, limit=nil)
    result = collection.find({}).skip(offset)
    result = result.limit(limit) if !limit.nil?
    result.collect { |doc|
      Place.new(doc)
    }
  end

  # Delete the document associated with its assigned id
  def destroy
    self.class.collection.find(:_id=>id_object).delete_one
  end

  # Return a collection of hash documents with address_components
  # and their associated _id, formatted_address and location properties.
  def self.get_address_components(sort=nil, offset=nil, limit=nil)
    pipeline=[{:$unwind=>"$address_components"},
      {:$project=>{_id:1, address_components:1, formatted_address:1, geometry: {geolocation:1}}}
    ]
    pipeline.push({:$sort=>sort}) if !sort.nil?
    pipeline.push({:$skip=>offset}) if !offset.nil?
    pipeline.push({:$limit=>limit}) if !limit.nil?
    collection.find.aggregate(pipeline)
  end

  # Return a distinct collection of country names (long_names)
  def self.get_country_names
    result = collection.find.aggregate([
      {:$unwind=>"$address_components"},
      {:$match=>{"address_components.types":"country"}},
      {:$project=>{address_components:{long_name:1, types:1}}},
      {:$group=>{:_id=>"$address_components.long_name"}}
    ])
    result.to_a.map {|h| h[:_id]}
  end

  # Return the id of each document in the places collection
  # that has an address_component.short_name of type country
  # and matches the provided parameter
  def self.find_ids_by_country_code(country_code)
    result = collection.find.aggregate([
      {:$match=>{ "address_components.types":"country",
                  "address_components.short_name":country_code
                }},
      {:$project=>{_id:1}}
    ])
    result.to_a.map {|doc| doc[:_id].to_s}
  end

  # Create a 2dsphere index for the geometry.geolocation property
  def self.create_indexes
    collection.indexes.create_one({"geometry.geolocation":Mongo::Index::GEO2DSPHERE})
  end

  # Remove a 2dsphere index for the geometry.geolocation property
  def self.remove_indexes
    collection.indexes.drop_one("geometry.geolocation_2dsphere")
  end

  # Returns places that are closest to the provided Point.
  def self.near(point, max_meters=nil)
    criteria = {"$geometry":point.to_hash}
    if !max_meters.nil?
      criteria[:$maxDistance] = max_meters
    end
    collection.find(
      "geometry.geolocation":{:$near=>criteria}
    )
  end

  # Wrap the class method near above for the current instance.
  def near(max_meters=nil)
    if (!@location.nil?)
      Place.to_places(Place.near(@location, max_meters))
    end
  end

  # Return a collection of Photos that have been associated with the place
  def photos(offset=0,limit=nil)
    result = Photo.find_photos_for_place(@id).skip(offset)
    result = result.limit(limit) if !limit.nil?
    return result.map { |doc| Photo.new(doc) }
  end
end
