# frozen_string_literal: true

module Veteran
  module Service
    module Constants
      METERS_PER_MILE = 1609.344
      DEFAULT_MAX_MILES = 50
      DEFAULT_MAX_DISTANCE = DEFAULT_MAX_MILES * METERS_PER_MILE

      FUZZY_SEARCH_THRESHOLD = 0.3 # pg_search's default

      MAX_PER_PAGE = 100
    end
  end
end
