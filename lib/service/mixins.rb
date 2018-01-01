

Thread.abort_on_exception = true

module Enumerable
  def every(n)
    (n - 1).step(self.size - 1, n).map { |i| self[i] }
  end
end
