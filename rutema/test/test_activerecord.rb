$:.unshift File.join(File.dirname(__FILE__),"..")
require 'test/unit'
require 'fileutils'
require 'patir/command'
require 'active_record'
require 'mocha'
require 'lib/rutema/models/activerecord'
require 'lib/rutema/reporters/activerecord'

module TestRutema
  class MockCommand
    include Patir::Command
    def initialize number
      @number=number
    end
  end
  class TestActiveRecordModel<Test::Unit::TestCase
    def setup
      ActiveRecord::Base.establish_connection(:adapter  => "sqlite3",:database =>":memory:")
      Rutema::ActiveRecord::Schema.up
    end
    def teardown
      ActiveRecord::Base.remove_connection
      FileUtils.rm_rf("db/") if File.exists?("db/")
    end
    #test the CRUD operations
    def test_create_read_update_delete
      #create
      r=Rutema::ActiveRecord::Run.new
      context={:tester=>"automatopoulos",:version=>"latest"}
      r.context=context
      sc=Rutema::ActiveRecord::Scenario.new(:name=>"TC000",:attended=>false,:status=>"success",:start_time=>Time.now)
      sc.steps<<Rutema::ActiveRecord::Step.new(:name=>"echo",:number=>1,:status=>"success",:output=>"testing is nice",:error=>"",:duration=>1)
      r.scenarios<<sc
      assert(r.save, "Failed to save.")
      #read
      run=Rutema::ActiveRecord::Run.find(r.id)
      assert_equal(context,run.context)
      assert_equal(sc.name, run.scenarios[0].name)
      #update
      new_context={:tester=>"tempelopoulos"}
      run.context=new_context
      assert(run.save, "Failed to update.")
      #delete
      assert(run.destroy, "Failed to delete.")
      assert_raise(ActiveRecord::RecordNotFound) {Rutema::ActiveRecord::Run.find(r.id)}
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
      @database={:db=>{:adapter=>"sqlite3",:database=>":memory:"}}
    end
    
    def teardown
      ::ActiveRecord::Base.remove_connection
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
      assert_equal(4, Rutema::ActiveRecord::Run.find(:all).size)
      assert_equal(8, Rutema::ActiveRecord::Scenario.find(:all).size)
      assert_equal(12, Rutema::ActiveRecord::Step.find(:all).size)
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
      r=Rutema::ActiveRecordReporter.new(@database)
      #without configuration
      assert_nothing_raised() { r.report({"test"=>spec},[state],[],nil)  }
      scenarios=Rutema::ActiveRecord::Scenario.find(:all)
      assert_equal(1, scenarios.size)
    end
  end
end