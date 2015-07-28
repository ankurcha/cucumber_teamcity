# Adapted from https://github.com/ankurcha/cucumber_teamcity


#
# When running scenario outlines you should run with --extend
#
# Possible callbacks:   https://github.com/sedadogan/cucumber/blob/c9f0c382a83b333e0dc3b62b450de54aeb641397/features/formatter_callbacks.feature
# Documentation:        http://www.rubydoc.info/gems/cucumber/1.2.1/Cucumber/Ast
# Example of callbacks: https://github.com/sedadogan/cucumber/blob/c9f0c382a83b333e0dc3b62b450de54aeb641397/lib/cucumber/formatter/pretty.rb
#

class TeamCityFormatter

  def initialize(step_mother, io, options)
    @io = io
    @options = options
    @current_scenario = nil
    @current_feature = nil
    @current_step=nil
    @any_scenario_succeeded=false
    reset_step_counters

    @err_io = StringIO.new
    $stderr = @err_io

    at_exit do
      scenario_finish
      feature_finish
      raise "No scenario succeeded" if not @any_scenario_succeeded
    end
  end

  def feature_name(the_word_feature, featureName)
    feature_finish if not @current_feature.nil?
    feature_start(featureName)
  end

  def scenario_name(keyword, name, file_colon_line, source_indent)
    if name =~ /\|/
      # ' | a   | b  | '  =>  '"a", "b"'
      comma_separated_arguments = name.strip.gsub(/^\|\s*/, '"').gsub(/\s*\|$/, '"').gsub(/\s*\|\s*/, '", "')
      scenario_name = "#{@scenario_outline} (#{comma_separated_arguments})"
    else
      scenario_name = %Q("#{name}")
    end
    scenario_finish if not @current_scenario.nil?
    scenario_start scenario_name
  end

  def step_name(keyword, step_match, status, source_indent, background, file_colon_line)
    line=format_step(keyword, step_match, status)
    @current_step=line

    case status
      when :passed
        @current_scenario_steps_passed+=1
      when :failed
        @current_scenario_steps_failed+=1
      when :undefined
        @err_io.puts "The cucumber parser could not understand one of the steps of this test."
        @current_scenario_steps_failed+=1
      else
        @current_scenario_steps_other+=1
    end

    step_message(line)
  end

  def before_outline_table(outline_table)
    @scenario_outline=@current_scenario
    @scenario_outline_row_number=0
    scenario_ignore_not_real

    @current_scenario = nil
  end

  def exception(exception, status)
    @err_io.puts format_exception(exception)
  end


  ######################################
  private
  ######################################

  
  def feature_start(name)
    @current_feature=teamcity_escape(name)
    print_stderr
    @io.puts "##teamcity[testSuiteStarted #{timestamp} name='#{@current_feature}']"
    @io.puts "##teamcity[progressMessage 'running feature: #{@current_feature}']"
    @io.flush
  end

  def feature_finish
    print_stderr
    @io.puts "##teamcity[testSuiteFinished #{timestamp} name='#{@current_feature}']"
    @io.flush
  end

  # log the start of a scenario
  def scenario_start(name)
    @current_scenario=teamcity_escape(name)
    print_stderr
    @io.puts "##teamcity[testStarted #{timestamp} name='#{@current_scenario}' captureStandardOutput='true']"
    @io.puts "##teamcity[progressMessage 'running scenario: #{@current_scenario}']"
    @io.flush
  end

  def scenario_finish
    if ((@current_scenario_steps_passed > 0) && (@current_scenario_steps_other == 0) && (@current_scenario_steps_failed == 0))
      scenario_succeed
    else
      scenario_fail(@current_scenario_steps_passed, @current_scenario_steps_other, @current_scenario_steps_failed)
    end
    reset_step_counters
  end

  def scenario_ignore_not_real
    @io.puts "##teamcity[testIgnored #{timestamp} name='#{@current_scenario}' message='This is a scenario outline, not a real scenario']"
    @io.flush
    reset_step_counters
  end

  # log the end of a scenario if succeeded
  def scenario_succeed
    @any_scenario_succeeded=true
    print_stderr
    @io.puts "##teamcity[testFinished #{timestamp} name='#{@current_scenario}']"
    @io.flush
  end

  # log the end of a scenario if failed
  def scenario_fail(steps_passed, steps_other, steps_failed)
    print_stderr
    @io.puts create_scenario_fail_output(@current_scenario, steps_passed, steps_other, steps_failed)
    @io.puts "##teamcity[testFinished #{timestamp} name='#{@current_scenario}']"
    @io.flush
  end

  def create_scenario_fail_output(name, steps_passed, steps_other, steps_failed)
    print_stderr
    message="#{steps_passed} steps passed, #{steps_failed} steps failed"
    message+=", #{steps_other} steps with other statuses" if steps_other > 0
    return "##teamcity[testFailed #{timestamp} name='#{name}' message='#{message}']"
  end

  def reset_step_counters
    @current_scenario_steps_passed = @current_scenario_steps_other = @current_scenario_steps_failed = 0
  end

  # add a message from step output to buffer
  # right now, type is ignored, since we have no reasonably
  # attractive way to add that to teamcity
  def step_message(msg)
    @io.puts "##teamcity[testStdOut name='#{@current_scenario}' out='#{teamcity_escape(msg)}']"
    @io.flush
  end


  def print_stderr
    if not @err_io.string.empty?
      @io.puts "##teamcity[testStdErr name='#{@current_scenario}' out='#{teamcity_escape(@err_io.string)}']"
      @err_io.truncate 0
    end
  end


  def format_step(keyword, step_match, status)
    %q{%s %10s %s %-90s @ %s} % [timestamp_short, status, keyword,
                                 step_match.format_args(lambda { |param| param }),
                                 step_match.file_colon_line]
  end

  def format_exception(exception)
    (["#{exception.message} (#{exception.class})"] + exception.backtrace).join("\n")
  end

  def format_table_row(row, status = :passed)
    #keep same basic formatting as format_step
    %q{%s %10s %-90s @ %s} % [timestamp_short, status, row.name, row.line]
  end

  # make necessary escapes for teamcity
  def teamcity_escape(str)
    str = str.to_s.strip
    str.gsub!('|', '||')
    str.gsub!("\n", '|n')
    str.gsub!("\r", '|r')
    str.gsub!("'", "|'")
    str.gsub!(']', '|]')
    return str
  end

  def timestamp_short
    t = Time.now
    ts=t.strftime('%H:%M:%S.%%0.3d') % (t.usec/1000)
  end

  def timestamp
    t = Time.now
    ts=t.strftime('%Y-%m-%dT%H:%M:%S.%%0.3d') % (t.usec/1000)
    " timestamp='#{ts}' "
  end

end
