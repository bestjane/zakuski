class Specification
	include Mongoid::Document
	include Mongoid::Timestamps

	field :title, type: String, localize: true
	field :description, type: String, localize: true

	attr_accessible :title, :description

	# validations
	validates :title, presence: true, length: {maximum: 10, minimum: 2}
	validates :description, presence: true, length: {minimum: 4, maximum: 256}

	embedded_in :custom_search_engine
end