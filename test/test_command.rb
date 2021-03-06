require 'helper'

class TestCommand < Test::Unit::TestCase
  context "when calling .globs" do
    context "when non-default dest & source dirs" do
      setup do
        @source = source_dir
        @dest   = dest_dir
        directory_with_contents(@dest)
        @globs  = Command.globs(@source, @dest)
      end
      should "return an array without the destination dir" do
        assert @globs.is_a?(Array)
        assert !@globs.include?(@dest)
      end
      teardown do
        clear_dest
      end
    end
    context "when using default dest dir" do
      setup do
        @source = test_dir
        @dest   = test_dir('_site')
        directory_with_contents(@dest)
        @globs  = Command.globs(@source, @dest)
      end
      should "return an array without the destination dir" do
        assert @globs.is_a?(Array)
        assert !@globs.include?(@dest)
        @globs.each do |glob|
           assert !glob.include?(File.basename(@dest))
        end
      end
      teardown do
        FileUtils.rm_r(@dest)
      end
    end
  end
  context "when calling .add_build_options" do
    should "add common options" do
      cmd = Object.new
      mock(cmd).option.with_any_args.at_least(1)
      Command.add_build_options(cmd)
    end
  end
  context "when calling .process_site" do
    context "when fatal error occurs" do
      should "exit with non-zero error code" do
        site = Object.new
        stub(site).process { raise Jekyll::FatalException }
        error = assert_raise(SystemExit) { Command.process_site(site) }
        assert_not_equal 0, error.status
      end
    end
  end
end
