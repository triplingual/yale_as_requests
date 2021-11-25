class AeonGridRow

  def initialize
    @data = {}
    @valid_columns = self.class.column_definitions.map{|col| [col.fetch('request_field'), true]}.to_h
    @request = nil
  end

  def set(column_name, value)
    raise "Not a column we know of: #{column_name}" unless @valid_columns.has_key?(column_name)
    @data[column_name] = value
  end

  def to_aeon_grid_row
    result = @valid_columns.map { |column_name, _|
      [column_name, @data.fetch(column_name, '').to_s]
    }.to_h

    result['request_json'] = serialize_request

    result
  end

  def self.column_definitions
    [
      {
        "title" => "Type",
        "request_field" => "item_type",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Repository",
        "request_field" => "repo_code",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Collection",
        "request_field" => "collection_title",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Series",
        "request_field" => "series_title",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Call Number",
        "request_field" => "call_number",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Container Title",
        "request_field" => "container_title",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Container Barcode",
        "request_field" => "container_barcode",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Location",
        "request_field" => "location",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Restrictions",
        "request_field" => "restrictions",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Item ID",
        "request_field" => "item_id",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Item Title",
        "request_field" => "item_title",
        "width" => 100,
        "type" => "string",
      },
      {
        "title" => "Published?",
        "request_field" => "published",
        "width" => 100,
        "type" => "string",
      },
    ]
  end

  def serialize_request
    raise "No request set" if @request.nil?

    requests = ASUtils.wrap(@request.delete('requests'))

    return @request if requests.empty?

    @request
      .merge(requests.first)
      .map{|k, v| [k, v.to_s]}
      .to_h
      .to_json
  end

end