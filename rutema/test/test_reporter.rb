$:.unshift File.join(File.dirname(__FILE__),"..","lib")
require 'rubygems'
require 'rutema/gems'
require 'test/unit'
require 'ostruct'
require 'fileutils'
require 'rutema/reporters/standard_reporters'
require 'mocha'
#$DEBUG=true
module TestRutema
  class MockCommand
    include Patir::Command
    def initialize number
      @number=number
    end
  end
  class TestActiveRecordReporter<Test::Unit::TestCase
    def setup
      @prev_dir=Dir.pwd
      Dir.chdir(File.dirname(__FILE__))
      @parse_errors=[{:filename=>"f.spec",:error=>"error"}]
      test1=Patir::CommandSequenceStatus.new("test1")
      test1.sequence_id=1
      test1.strategy=:attended
      test2=Patir::CommandSequenceStatus.new("test2")
      test2.sequence_id=2
      test2.strategy=:unattended
      test1.step=MockCommand.new(1)
      test2.step=MockCommand.new(2)
      test2.step=MockCommand.new(3)
      @status=[test1,test2]
      @database={:db=>{:database=>":memory:"}}
      @database={:db=>{:database=>"db/h2"}} if RUBY_PLATFORM =~ /java/
    end
    def teardown
      ActiveRecord::Base.remove_connection
      FileUtils.rm_rf("db")
      Dir.chdir(@prev_dir)
    end
    def test_report
      spec1=OpenStruct.new(:name=>"test1")
      spec2=OpenStruct.new(:name=>"test2",:version=>"10")
      specs={"test1"=>spec1,
        "test2"=>spec2
      }
      r=Rutema::ActiveRecordReporter.new(@database)
      #without configuration
      assert_nothing_raised() { r.report(specs,@status,@parse_errors,nil)  }
      configuration=OpenStruct.new
      #without context member
      assert_nothing_raised() { r.report(specs,@status,@parse_errors,configuration)  }
      #with a nil context
      configuration.context=nil
      assert_nothing_raised() { r.report(specs,@status,@parse_errors,configuration)  }
      #with some context
      configuration.context="context"
      assert_nothing_raised() { r.report(specs,@status,@parse_errors,configuration)  }
      assert_equal(4, Rutema::Model::Run.find(:all).size)
      assert_equal(8, Rutema::Model::Scenario.find(:all).size)
      assert_equal(12, Rutema::Model::Step.find(:all).size)
    end

    def test_sql_injection
      spec=mock()
      spec.expects(:has_version?).returns(false)
      spec.expects(:title).returns("test")
      spec.expects(:description).returns("sql injection test")
      step_state1={:name=>"step 1",:output=>"'injected '' ''",:error=>"'more injection ''' '''"}
      step_state2={:name=>"step 2",:output=>"With breaks\nand other stuff",:error=>"\nlots of\nbreaks"}
      step_state3={:name=>"step 3",:output=>" "}
      state=mock()
      state.expects(:sequence_name).returns("test").times(2)
      state.expects(:sequence_id).returns(1)
      state.expects(:start_time).returns(Time.now)
      state.expects(:stop_time).returns(Time.now)
      state.expects(:status).returns(:success)
      state.expects(:strategy).returns()
      state.expects(:step_states).returns({1=>step_state1, 2=>step_state2,3=>step_state3})
      r=Rutema::ActiveRecordReporter.new(:db=>{:database=>":memory:"})
      #without configuration
      assert_nothing_raised() { r.report({"test"=>spec},[state],[],nil)  }
      scenarios=Rutema::Model::Scenario.find(:all)
      assert_equal(1, scenarios.size)
    end
  end
  class TestEmailReporter<Test::Unit::TestCase
    def setup
      @parse_errors=[{:filename=>"f.spec",:error=>"error"}]
      st=Patir::CommandSequenceStatus.new("test_seq")
      st.step=MockCommand.new(1)
      st.step=MockCommand.new(2)
      st.step=MockCommand.new(3)
      @status=[st]
    end
    def test_new
      spec=mock()
      spec.expects(:title).returns("A test sequence")
      specs={"test_seq"=>spec}
      definition={:server=>"localhost",:port=>25,:recipients=>["test"],:sender=>"rutema",:subject=>"test",:footer=>"footer"}
      r=Rutema::EmailReporter.new(definition)
      Net::SMTP.expects(:start).times(2)
      assert_nothing_raised() { puts r.report(specs,@status,@parse_errors,nil) }
      assert_nothing_raised() { puts r.report(specs,[],[],nil) }
    end

    def test_multiple_scenarios
      #The status mocks
      status1=status_mock("test6. Status - error. States 3\nStep status summary:\n\t1:'echo' - success\n\t2:'check' - warning\n\t3:'try' - error",6,"T2",:error)
      
      status2=status_mock("test10. Status - success. States 3\nStep status summary:\n\t1:'echo' - success\n\t2:'check' - success\n\t3:'try' - success",10,"T1",:success)
      status3=status_mock("testNil. Status - success. States 3\nStep status summary:\n\t1:'echo' - success\n\t2:'check' - success\n\t3:'try' - success",nil,nil,:success)
      status4=status_mock("test10s. Status - success. States 3\nStep status summary:\n\t1:'echo' - success\n\t2:'check' - success\n\t3:'try' - success","10s","Setup",:success)
      status5=status_mock("test60. Status - error. States 3\nStep status summary:\n\t1:'echo' - success\n\t2:'check' - warning\n\t3:'try' - error",60,"T1",:error)
      stati=[status1,status2,status3,status4,status5]
      p stati
      #mock the mailing code
      definition={:server=>"localhost",:port=>25,:recipients=>["test"],:sender=>"rutema",:subject=>"test"}
      r=Rutema::EmailReporter.new(definition)
      Net::SMTP.expects(:start)
      #The specification mocks
      spec1=mock()
      spec1.expects(:title).times(2).returns("T1")
      spec2=mock()
      spec2.expects(:title).returns("T2")
      spec3=mock()
      spec3.expects(:title).returns("Setup")
      specs={"T1"=>spec1, "T2"=>spec2, "Setup"=>spec3}
      puts r.report(specs,stati,@parse_errors,nil)
    end
    
    def status_mock summary,id,name,state
      ret=mock()
      ret.expects(:summary).returns(summary)
      ret.expects(:sequence_id).returns(id)
      if name
        ret.expects(:sequence_name).returns(name).times(2)
      else
        ret.expects(:sequence_name).returns(name)
      end
      ret.expects(:status).returns(state).times(4)
      return ret
    end
  end

  class TestTextReporter<Test::Unit::TestCase
      def setup
        @parse_errors=[{:filename=>"f.spec",:error=>"error"}]
        st=Patir::CommandSequenceStatus.new("test_seq")
        st.step=MockCommand.new(1)
        st.step=MockCommand.new(2)
        st.step=MockCommand.new(3)
        @status=[st]
      end
      
      def test_no_errors
        spec=mock
        spec.expects(:title).returns("T").times(2)
        success1 = scenario_mock(1)
        success2 = scenario_mock(2)
        r=Rutema::TextReporter.new
        assert_nothing_raised() { puts r.report({"test"=>spec},runner_state_mock(2,[],[success1,success2],[],[]),[],nil) }
      end
      
      def test_a_bit_of_everything
        spec=mock
        spec.expects(:title).returns("T").times(4)
        success = scenario_mock(1)
        failure = scenario_mock(2)
        warning = scenario_mock(3)
        not_run = scenario_mock(3,true) 
        r=Rutema::TextReporter.new
        puts r.report({"test"=>spec},runner_state_mock(4,[not_run],[success],[failure],[warning]),[],nil)
      end
      
      
      def scenario_mock id,no_summary=false
        ret = mock()
        ret.expects(:sequence_id).returns(id)
        ret.expects(:sequence_name).returns("test").times(2)
        ret.expects(:summary).returns("summary") unless no_summary
        return ret
      end
      
      def runner_state_mock size, not_run,successes,warnings,failures
        runner_state=mock()
        runner_state.expects(:empty?).returns(false)
        runner_state.expects(:size).returns(size).times(3)
        
        runner_state.expects(:select).returns(failures)
        runner_state.expects(:select).returns(warnings)
        runner_state.expects(:select).returns(successes)
        runner_state.expects(:select).returns(not_run)
        
        return runner_state
      end
  end
end