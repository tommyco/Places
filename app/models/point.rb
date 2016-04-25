class Point
	attr_accessor :longitude, :latitude

	# set the attributes from a hash with keys :lat & :lng
	# or a GeoJSON Point format
	def initialize(geo_point)
		if geo_point.key?(:lat) && geo_point.key?(:lng)
			@latitude = geo_point[:lat]
			@longitude = geo_point[:lng]
		else
			@longitude = geo_point[:coordinates][0]
			@latitude = geo_point[:coordinates][1]
		end
	end

	# generate a GeoJSON Point hash
	def to_hash
		return {"type":"Point", "coordinates":[@longitude, @latitude]}
	end
end