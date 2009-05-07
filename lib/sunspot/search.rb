module Sunspot
  # 
  # This class encapsulates the results of a Solr search. It provides access
  # to search results, total result count, facets, and pagination information.
  # Instances of Search are returned by the Sunspot.search method.
  #
  class Search
    RawResult = Struct.new(:class_name, :primary_key)

    attr_reader :query

    #XXX should types be passed in here? should we pass in a Query instance?
    def initialize(connection, query) #:nodoc:
      @connection = connection
      @query = query
    end

    #
    # Execute the search on the Solr instance and store the results
    #
    def execute! #:nodoc:
      params = @query.to_params
      @solr_result = @connection.query(params.delete(:q), params)
      self
    end

    # 
    # Get the collection of results as instantiated objects. If WillPaginate is
    # available, the results will be a WillPaginate::Collection instance; if
    # not, it will be a vanilla Array.
    #
    # ==== Returns
    #
    # WillPaginate::Collection or Array:: Instantiated result objects
    #
    def results
      @results ||= if @query.page && defined?(WillPaginate::Collection)
        WillPaginate::Collection.create(@query.page, @query.per_page, @solr_result.total_hits) do |pager|
          pager.replace(result_objects)
        end
      else
        result_objects
      end
    end

    # 
    # Access raw results without instantiating objects from persistent storage.
    # This may be useful if you are using search as an intermediate step in data
    # retrieval. Returns an ordered collection of objects that respond to
    # #class_name and #primary_key
    #
    # ==== Returns
    #
    # Array:: Ordered collection of raw results
    #
    def raw_results
      @raw_results ||= hit_ids.map { |hit_id| RawResult.new(*hit_id.match(/([^ ]+) (.+)/)[1..2]) }
    end

    # 
    # The total number of documents matching the query parameters
    #
    # ==== Returns
    #
    # Integer:: Total matching documents
    #
    def total
      @total ||= @solr_result.total_hits
    end

    # 
    # Get the facet object for the given field. This field will need to have
    # been requested as a field facet inside the search block.
    #
    # ==== Parameters
    #
    # field_name<Symbol>:: field name for which to get the facet
    #
    # ==== Returns
    #
    # Sunspot::Facet:: Facet object for the given field
    #
    def facet(field_name)
      (@facets_cache ||= {})[field_name.to_sym] ||=
        begin
          field = @query.field(field_name)
          Facet.new(@solr_result.field_facets(field.indexed_name), field)
        end
    end

    private

    # 
    # Collection of instantiated result objects corresponding to the results
    # returned by Solr.
    #
    # ==== Returns
    #
    # Array:: Collection of instantiated result objects
    #
    def result_objects
      raw_results.inject({}) do |type_id_hash, raw_result|
        (type_id_hash[raw_result.class_name] ||= []) << raw_result.primary_key
        type_id_hash
      end.inject([]) do |results, pair|
        type_name, ids = pair
        results.concat(Adapters::DataAccessor.create(Util.full_const_get(type_name)).load_all(ids))
      end.sort_by do |result|
        hit_ids.index(Adapters::InstanceAdapter.adapt(result).index_id)
      end
    end

    def hit_ids
      @hit_ids ||= @solr_result.hits.map { |hit| hit['id'] }
    end
  end
end