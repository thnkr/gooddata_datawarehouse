require 'jdbc/dss'
require 'sequel'
require 'logger'
require 'csv'

require_relative 'sql_generator'

module GoodData
  class Datawarehouse
    def initialize(username, password, instance_id, options={})
      @logger = Logger.new(STDOUT)
      @username = username
      @password = password
      @jdbc_url = "jdbc:dss://secure.gooddata.com/gdc/dss/instances/#{instance_id}"
      Jdbc::DSS.load_driver
      Java.com.gooddata.dss.jdbc.driver.DssDriver
    end

    def export_table(table_name, csv_path)
      CSV.open(csv_path, 'wb', :force_quotes => true) do |csv|
        # get the names of cols
        cols = get_columns(table_name).map {|c| c[:column_name]}
        col_names =

        # write header
        csv << cols

        # get the keys for columns, stupid sequel
        col_keys = nil
        rows = execute_select(GoodData::SQLGenerator.select_all(table_name, limit: 1))

        col_keys = rows[0].keys

        execute_select(GoodData::SQLGenerator.select_all(table_name)) do |row|
          # go through the table write to csv
          csv << row.values_at(*col_keys)
        end
      end
    end

    def rename_table(old_name, new_name)
      execute(GoodData::SQLGenerator.rename_table(old_name, new_name))
    end

    def drop_table(table_name, opts={})
      execute(GoodData::SQLGenerator.drop_table(table_name,opts))
    end

    def csv_to_new_table(table_name, csv_path, opts={})
      cols = create_table_from_csv_header(table_name, csv_path, opts)
      load_data_from_csv(table_name, csv_path, columns: cols)
    end

    def load_data_from_csv(table_name, csv_path, opts={})
      columns = opts[:columns] || get_csv_headers(csv_path)
      execute(GoodData::SQLGenerator.load_data(table_name, csv_path, columns))
    end

    # returns a list of columns created
    # does nothing if file empty, returns []
    def create_table_from_csv_header(table_name, csv_path, opts={})
      # take the header as a list of columns
      columns = get_csv_headers(csv_path)
      create_table(table_name, columns, opts) unless columns.empty?
      columns
    end

    def create_table(name, columns, options={})
      execute(GoodData::SQLGenerator.create_table(name, columns, options))
    end

    def table_exists?(name)
      count = execute_select(GoodData::SQLGenerator.get_table_count(name), :count => true)
      count > 0
    end

    def get_columns(table_name)
      res = execute_select(GoodData::SQLGenerator.get_columns(table_name))
    end

    # execute sql, return nothing
    def execute(sql_strings)
      if ! sql_strings.kind_of?(Array)
        sql_strings = [sql_strings]
      end
      connect do |connection|
        sql_strings.each do |sql|
          @logger.info("Executing sql: #{sql}") if @logger
          connection.run(sql)
        end
      end
    end

    # executes sql (select), for each row, passes execution to block
    def execute_select(sql, options={})
      fetch_handler = options[:fetch_handler]
      count = options[:count]

      connect do |connection|
        # do the query
        f = connection.fetch(sql)

        @logger.info("Executing sql: #{sql}") if @logger
        # if handler was passed call it
        if fetch_handler
          fetch_handler.call(f)
        end

        if count
          return f.first[:count]
        end

        # if block given yield to process line by line
        if block_given?
          # go through the rows returned and call the block
          return f.each do |row|
            yield(row)
          end
        end

        # return it all at once
        f.map{|h| h}
      end
    end

    def connect
      Sequel.connect @jdbc_url,
        :username => @username,
        :password => @password do |connection|
          yield(connection)
      end
    end

    private

    def get_csv_headers(csv_path)
      header_str = File.open(csv_path, &:gets)
      if header_str.nil? || header_str.empty?
        return []
      end
      header_str.split(',').map{ |s| s.gsub(/[\s"-]/,'') }
    end
  end
end
