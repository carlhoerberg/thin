require 'rubygems'
require File.dirname(__FILE__) + '/../lib/thin'
require 'spec'
require 'benchmark'
require 'timeout'
require 'fileutils'
require 'benchmark_unit'

include Thin

FileUtils.mkdir_p File.dirname(__FILE__) + '/../log'

class TestRequest < Thin::Request
  def initialize(path, verb='GET', params={})
    @path = path
    @verb = verb.to_s.upcase
    @params = {
      'HTTP_HOST'      => 'localhost:3000',
      'REQUEST_URI'    => @path,
      'REQUEST_PATH'   => @path,
      'REQUEST_METHOD' => @verb,
      'SCRIPT_NAME'    => @path
    }.merge(params)
    
    @body = "#{@verb} #{path} HTTP/1.1"
  end
end

module Matchers
  class BeFasterThen
    def initialize(max_time)
      @max_time = max_time
    end

    # Base on benchmark_unit/assertions#compare_benchmarks
    def matches?(proc)
      @time, multiplier = 0, 1
      
      while (@time < 0.01) do
        @time = Benchmark::Unit.measure do 
          multiplier.times &proc
        end
        multiplier *= 10
      end
      
      multiplier /= 10
      
      iterations = (Benchmark::Unit::CLOCK_TARGET / @time).to_i * multiplier
      iterations = 1 if iterations < 1
      
      total = Benchmark::Unit.measure do 
        iterations.times &proc
      end
      
      @time = total / iterations
      
      @time < @max_time
    end
    
    def failure_message(less_more=:less)
      "took <#{@time.inspect} RubySeconds>, should take #{less_more} than #{@max_time} RubySeconds."
    end

    def negative_failure_message
      failure_message :more
    end
  end
  
  class ValidateWithLint
    def matches?(request)
      @request = request
      Rack::Lint.new(proc{[200, {'Content-Type' => 'text/html'}, []]}).call(@request.env)
      true
    rescue Rack::Lint::LintError => e
      @message = e.message
      false
    end
    
    def failure_message(negation=nil)
      "should#{negation} validate with Rack Lint"
    end

    def negative_failure_message
      failure_message ' not'
    end
  end

  class TakeLessThen
    def initialize(time)
      @time = time
    end
    
    def matches?(proc)
      Timeout.timeout(@time) { proc.call }
      true
    rescue Timeout::Error
      false 
    end
    
    def failure_message(negation=nil)
      "should#{negation} take less then #{@time} sec to run"
    end

    def negative_failure_message
      failure_message ' not'
    end
  end

  # Actual matchers that are exposed.

  def be_faster_then(time)
    BeFasterThen.new(time)
  end
  
  def validate_with_lint
    ValidateWithLint.new
  end

  def take_less_then(time)
    TakeLessThen.new(time)
  end  
end

module Helpers
  # Silences any stream for the duration of the block.
  #
  #   silence_stream(STDOUT) do
  #     puts 'This will never be seen'
  #   end
  #
  #   puts 'But this will'
  #
  # (Taken from ActiveSupport)
  def silence_stream(stream)
    old_stream = stream.dup
    stream.reopen(RUBY_PLATFORM =~ /mswin/ ? 'NUL:' : '/dev/null')
    stream.sync = true
    yield
  ensure
    stream.reopen(old_stream)
  end
end

Spec::Runner.configure do |config|
  config.include Matchers
  config.include Helpers
end