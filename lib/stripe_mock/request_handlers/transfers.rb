module StripeMock
  module RequestHandlers
    module Transfers

      def Transfers.included(klass)
        klass.add_handler 'post /v1/transfers',             :new_transfer
        klass.add_handler 'get /v1/transfers',              :get_all_transfers
        klass.add_handler 'post /v1/transfers/(.*)/cancel', :cancel_transfer
        klass.add_handler 'post /v1/transfers/(.*)/reversals',     :new_transfer_reversal
        klass.add_handler 'get /v1/transfers/(.*)/reversals',      :get_all_transfer_reversals
        klass.add_handler 'get /v1/transfers/(.*)/reversals/(.*)', :get_transfer_reversal
        klass.add_handler 'get /v1/transfers/(.*)',         :get_transfer
      end

      def get_all_transfers(route, method_url, params, headers)
        extra_params = params.keys - [:created, :destination, :ending_before,
          :limit, :starting_after, :transfer_group]
        unless extra_params.empty?
          raise Stripe::InvalidRequestError.new("Received unknown parameter: #{extra_params[0]}", extra_params[0].to_s, http_status: 400)
        end

        if destination = params[:destination]
          assert_existence :destination, destination, accounts[destination]
        end

        _transfers = transfers.each_with_object([]) do |(_, transfer), array|
          if destination
            array << transfer if transfer[:destination] == destination
          else
            array << transfer
          end
        end

        if params[:limit]
          _transfers = _transfers.first([params[:limit], _transfers.size].min)
        end

        Data.mock_list_object(_transfers, params)
      end

      def new_transfer(route, method_url, params, headers)
        id = new_id('tr')
        if params[:bank_account]
          params[:account] = get_bank_by_token(params.delete(:bank_account))
        end

        unless params[:amount].is_a?(Integer) || (params[:amount].is_a?(String) && /^\d+$/.match(params[:amount]))
          raise Stripe::InvalidRequestError.new("Invalid integer: #{params[:amount]}", 'amount', http_status: 400)
        end

        bal_trans_params = { amount: params[:amount].to_i, source: id }

        balance_transaction_id = new_balance_transaction('txn', bal_trans_params)

        transfers[id] = Data.mock_transfer(params.merge(id: id, balance_transaction: balance_transaction_id))

        transfer = transfers[id].clone
        if params[:expand] == ['balance_transaction']
          transfer[:balance_transaction] = balance_transactions[balance_transaction_id]
        end

        transfer
      end

      def get_transfer(route, method_url, params, headers)
        route =~ method_url
        assert_existence :transfer, $1, transfers[$1]
        transfers[$1] ||= Data.mock_transfer(:id => $1)
      end

      def cancel_transfer(route, method_url, params, headers)
        route =~ method_url
        assert_existence :transfer, $1, transfers[$1]
        t = transfers[$1] ||= Data.mock_transfer(:id => $1)
        t.merge!({:status => "canceled"})
      end

      def get_all_transfer_reversals(route, method_url, params, headers)
        extra_params = params.keys - [:ending_before, :limit, :starting_after]
        unless extra_params.empty?
          raise Stripe::InvalidRequestError.new("Received unknown parameter: #{extra_params[0]}", extra_params[0].to_s, http_status: 400)
        end
 
        if params[:limit]
          transfer_reversals = transfer_reversals.first([params[:limit], transfer_reversals.size].min)
        end
 
        Data.mock_list_object(transfer_reversals, params)
      end
 
      def new_transfer_reversal(route, method_url, params, headers)
        route =~ method_url
        id = new_id('trr')
  
        unless params[:amount].is_a?(Integer) || (params[:amount].is_a?(String) && /^\d+$/.match(params[:amount]))
          raise Stripe::InvalidRequestError.new("Invalid integer: #{params[:amount]}", 'amount', http_status: 400)
        end
 
        transfer = assert_existence :transfer, $1, transfers[$1]
        transfer_reversal = Data.mock_transfer_reversal(params.merge :id => id)
        transfer[:reversals][:data] << transfer_reversal
        transfer[:reversals][:total_count] = transfer[:reversals][:data].length
        transfer_reversal
      end
 
      def get_transfer_reversal(route, method_url, params, headers)
        route =~ method_url
        transfer = assert_existence :transfer, $1, transfers[$1]
        transfer_reversal = transfer[:reversals][:data].find{|trr| trr[:id] == $2 }
      end
    end
  end
end
