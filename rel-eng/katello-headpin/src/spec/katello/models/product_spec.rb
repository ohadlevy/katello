#
# Copyright 2011 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

require 'spec_helper'
require 'helpers/product_test_data'

include OrchestrationHelper

describe Product do

  before(:each) do
    disable_org_orchestration

    @organization = Organization.create!(:name => ProductTestData::ORG_ID, :cp_key => 'admin-org-37070')
    @provider     = @organization.redhat_provider
    @substitutor_mock = mock
    @substitutor_mock.stub!(:substitute_vars).and_return do |path|
      {{} =>  path}
    end

    CDN::CdnVarSubstitutor.stub(:new => @substitutor_mock)
    CDN::CdnResource.stub(:ca_file => "#{Rails.root}/config/candlepin-ca.crt")
    OpenSSL::X509::Certificate.stub(:new).and_return(&:to_s)
    OpenSSL::PKey::RSA.stub(:new).and_return(&:to_s)

    ProductTestData::SIMPLE_PRODUCT.merge!({:provider => @provider, :environments => [@organization.locker]})
    ProductTestData::SIMPLE_PRODUCT_WITH_INVALID_NAME.merge!({:provider => @provider, :environments => [@organization.locker]})
    ProductTestData::PRODUCT_WITH_ATTRS.merge!({:provider => @provider, :environments => [@organization.locker]})
    ProductTestData::PRODUCT_WITH_CONTENT.merge!({:provider => @provider, :environments => [@organization.locker]})
  end

  describe "create product" do

    context "new product" do
      before(:each) { @p = Product.new({}) }
      specify { @p.productContent.should == [] }
    end

    context "with valid parameters" do
      before(:each) do
        disable_product_orchestration
        @p = Product.create!(ProductTestData::SIMPLE_PRODUCT)
      end

      specify { @p.name.should == ProductTestData::SIMPLE_PRODUCT['name'] }
      specify { @p.created_at.should_not be_nil }
      specify { @p.environments.should include(@organization.locker) }
    end

    context "candlepin orchestration" do
      before do
        Candlepin::Product.stub!(:certificate).and_return("")
        Candlepin::Product.stub!(:key).and_return("")
        Pulp::Repository.stub!(:create).and_return([])
      end

      context "with attributes" do
        it "should create product in katello" do

          expected_product = {
              :attributes => ProductTestData::PRODUCT_WITH_ATTRS[:attributes],
              :multiplier => ProductTestData::PRODUCT_WITH_ATTRS[:multiplier],
              :name => ProductTestData::PRODUCT_WITH_ATTRS[:name]
          }

          Candlepin::Product.should_receive(:create).once.with(hash_including(expected_product)).and_return({:id => 1})
          product = Product.create!(ProductTestData::PRODUCT_WITH_ATTRS)
          product.organization.should_not be_nil
        end
      end

      context "with content" do
        it "should create product in katello" do
          expected_content = ProductTestData::PRODUCT_WITH_CONTENT[:productContent][0].content

          Candlepin::Product.stub!(:create).and_return({:id => ProductTestData::PRODUCT_ID})
          Candlepin::Content.should_receive(:create)                \
              .once.with(an_instance_of(Glue::Candlepin::Content))  \
              .and_return({:id => ProductTestData::PRODUCT_WITH_CONTENT[:productContent][0].content.id})
                # don't know how to verify equality
              #c.name == 'aa' #expected_content[:name]
              #c.id = expected_content[:id]
              #c.type = expected_content[:type]
              #c.label = expected_content[:label]
              #c.vendor = expected_content[:vendor]
              #c.contentUrl = expected_content[:contentUrl]
              #c.gpgUrl = expected_content[:gpgUrl]
          Candlepin::Product.
              should_receive(:add_content).once.
              with(
                ProductTestData::PRODUCT_ID,
                ProductTestData::PRODUCT_WITH_CONTENT[:productContent][0].content.id,
                ProductTestData::PRODUCT_WITH_CONTENT[:productContent][0].enabled
              ).and_return({})

          p = Product.create!(ProductTestData::PRODUCT_WITH_CONTENT)
        end
      end

    end
  end

  context "product repos" do
    before(:each) do
      disable_product_orchestration
    end

    describe "add repo" do
      before(:each) do
        Candlepin::Product.stub!(:create).and_return({:id => ProductTestData::PRODUCT_ID})
        @p = Product.create!(ProductTestData::SIMPLE_PRODUCT)
      end

      context "when there is a repo with the same name for the product" do
        before do
          @repo_name = "repo"
        end

        it "should raise conflict error" do
          @p.should_receive(:repos).with(@p.locker, {:name => "repo"}).and_return([Glue::Pulp::Repo.new(:id => "123")])
          lambda { @p.add_new_content("repo", "http://test/repo","yum") }.should raise_error(Errors::ConflictException)
        end
      end
    end

    context "when importing product from candlepin" do
      before do
        Candlepin::Product.stub!(:create).and_return({:id => ProductTestData::PRODUCT_ID})
        Candlepin::Content.stub!(:create).and_return({:id => "123"})
        @repo = Glue::Pulp::Repo.new(:id => '123')
        Glue::Pulp::Repo.stub(:new).and_return(@repo)
      end

      it "prepares valid name for Pulp repo" do
          Glue::Pulp::Repo.should_receive(:new).once.with(hash_including(:name => 'some-name33'))
          p = Product.new(ProductTestData::PRODUCT_WITH_CONTENT)
          p.orchestration_for = :import_from_cp
          p.save!
      end

     context "product has more archs" do
       after do
         @substitutor_mock.stub!(:substitute_vars).and_return do |path|
           ret = {}
           [{"releasever" => "6Server", "basearch" => "i386"},
            {"releasever" => "6Server", "basearch" => "x86_64"}].each do |substitutions|
             ret[substitutions] = substitutions.inject(path) {|new_path,(var,val)| new_path.gsub("$#{var}", val)}
            end
           ret
         end
         p = Product.new(ProductTestData::PRODUCT_WITH_CONTENT)
         p.stub(:attrs => [{:name => 'arch', :value => 'x86_64,i386'}])
         p.orchestration_for = :import_from_cp
         p.save!
       end

       it "should create repo for each arch" do
         Glue::Pulp::Repo.should_receive(:new).once.with(hash_including(:name => 'some-name33 6Server x86_64'))
         Glue::Pulp::Repo.should_receive(:new).once.with(hash_including(:name => 'some-name33 6Server i386'))
       end

       it "should substitute $basearch in the contentUrl for the repo feed" do
         expected_feed = "#{@provider.repository_url}/released-extra/RHEL-5-Server/6Server/x86_64/os/ClusterStorage/"
         Glue::Pulp::Repo.should_receive(:new).once.with(hash_including(:feed => expected_feed)).and_return(@repo)
       end
     end

    end
  end
end