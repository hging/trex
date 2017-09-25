class Wallet
  def update_gdax
    return if @enable_gdax
    @enable_gdax = true

    Thread.new do
      begin
        loop do
          [:LTC, :ETH, :BTC].each do |coin|
            obj = JSON.parse(open("https://api.gdax.com/products/#{coin}-USD/ticker").read)
            @gdax[coin] = obj["price"].to_f
          end
          sleep 1.1
        end
      rescue => e
        message e.to_s
      end
    end
  end

  on_init do
    @gdax = {}
    update_gdax if ARGV.index("--gdax-rates") or ARGV.index("--enable-gdax-rates")
    @btc_rate_override = "gdax" if ARGV.index("--gdax-rates")
  end
end
