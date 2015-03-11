require 'spec_helper'
require 'oat/adapters/json_api'

describe Oat::Adapters::JsonAPI do

  include Fixtures

  let(:serializer) { jsonapi_serializer_class.new(user, {:name => 'some_controller'}, Oat::Adapters::JsonAPI) }
  let(:hash) { serializer.to_hash }

  describe '#to_hash' do
    context 'top level' do
      subject(:data){ hash.fetch(:data) }

      it 'contains the correct user properties' do
        expect(data).to match(
          :id => user.id,
          :type => :users,
          :name => user.name,
          :age => user.age,
          :controller_name => 'some_controller',
          :message_from_above => nil,
          :links => {
            :self => 'http://foo.bar.com/1',
            :empty => nil,
            :friends => {
              :type => 'users',
              :id => ['2']
            },
            :manager => {
              :id => '3',
              :type => 'managers'
            }
          }
        )
      end

      it 'contains the correct user links' do
        expect(data.fetch(:links)).to include(
          :self => "http://foo.bar.com/#{user.id}",
          :empty => nil,
          # these links are added by embedding entities
          :manager => {id: manager.id.to_s, type: 'managers'},
          :friends => {type: 'users', id: [friend.id.to_s]}
        )
      end
    end

    context 'meta' do
      subject(:meta) { hash.fetch(:meta) }

      it 'contains meta properties' do
        expect(meta[:nation]).to eq('zulu')
      end

      context 'without meta' do
        let(:jsonapi_serializer_class) {
           Class.new(Oat::Serializer) do
              schema do
                type 'users'
              end
            end
        }

        it 'does not contain meta information' do
          expect(hash[:meta]).to be_nil
        end
      end
    end

    context 'included' do
      context 'using #entities' do
        subject(:included_friends){ hash.fetch(:included).select {|item| item[:type] == :users} }

        its(:size) { should eq(1) }

        it 'contains the correct properties' do
          expect(included_friends.first).to include(
            :id => friend.id,
            :type => :users,
            :name => friend.name,
            :age => friend.age,
            :controller_name => 'some_controller',
            :message_from_above => 'Merged into parent\'s context',
            :links => {:self => 'http://foo.bar.com/2', :empty => nil}
          )
        end

        it 'contains the correct links' do
          expect(included_friends.first.fetch(:links)).to include(
            :self => "http://foo.bar.com/#{friend.id}"
          )
        end
      end

      context 'using #entity' do
        subject(:included_managers){ hash.fetch(:included).select {|item| item[:type] == :managers} }

        it 'does not duplicate an entity that is associated with 2 objects' do
          expect(included_managers.size).to eq(1)
        end

        it 'contains the correct properties and links' do
          expect(included_managers.first).to match(
            :id => manager.id,
            :type => :managers,
            :name => manager.name,
            :age => manager.age,
            :links => { :self => "http://foo.bar.com/#{manager.id}" }
          )
        end
      end

      context 'with nested entities' do
        let(:friend) { user_class.new('Joe', 33, 2, [other_friend]) }
        let(:other_friend) { user_class.new('Jack', 28, 4, []) }

        subject(:included_friends){ hash.fetch(:included).select {|item| item[:type] == :users} }
        its(:size) { should eq(2) }

        it 'has the correct entities' do
          expect(included_friends.map{ |friend| friend.fetch(:id) }).to include(2, 4)
        end
      end
    end

    context 'object links' do

      context 'special keys' do
        context 'self' do
          context 'as string' do
            let(:jsonapi_serializer_class) do
              Class.new(Oat::Serializer) do
                schema do
                  type 'users'
                  link :self, "/resources/45"
                end
              end
            end

            it 'renders just the string' do
              expect(hash.fetch(:data).fetch(:links)).to eq(:self => '/resources/45')
            end
          end

          context 'as array' do
            let(:jsonapi_serializer_class) do
              Class.new(Oat::Serializer) do
                schema do
                  type 'users'
                  link :self, ['45']
                end
              end
            end

            it 'errs' do
              expect{hash}.to raise_error
            end
          end

          context 'as hash' do
            let(:jsonapi_serializer_class) do
              Class.new(Oat::Serializer) do
                schema do
                  type 'users'
                  link :self, { :href => '/resources/45' }
                end
              end
            end

            it 'errs' do
              expect{hash}.to raise_error
            end
          end
        end
      end

      context 'as string' do
        let(:jsonapi_serializer_class) do
          Class.new(Oat::Serializer) do
            schema do
              type 'users'
              link :friends, '/friends/45'
            end
          end
        end

        it 'renders just the string' do
          expect(hash.fetch(:data).fetch(:links)).to eq(:friends => '/friends/45')
        end
      end

      context 'as array' do
        let(:jsonapi_serializer_class) do
          Class.new(Oat::Serializer) do
            schema do
              type 'users'
              link :friends, ['45']
            end
          end
        end

        it 'errs' do
          expect{hash}.to raise_error
        end
      end

      context 'as hash' do
        context 'with single id' do
          let(:jsonapi_serializer_class) do
            Class.new(Oat::Serializer) do
              schema do
                type 'users'
                link :friend,
                     :self => "http://foo.bar.com/#{item.id}/links/friend",
                     :related => "http://foo.bar.com/#{item.id}/friend",
                     :id => item.id.to_s,
                     :type => 'user'
              end
            end
          end

          it 'renders all the keys' do
            expect(hash.fetch(:data).fetch(:links)).to eq({
              :friend => {
                :self => 'http://foo.bar.com/1/links/friend',
                :related => 'http://foo.bar.com/1/friend',
                :id => user.id.to_s,
                :type => 'user'
              }
            })
          end
        end

        context 'with multiple ids' do
          let(:jsonapi_serializer_class) do
            Class.new(Oat::Serializer) do
              schema do
                type 'users'
                link :friends,
                     :self => "http://foo.bar.com/#{item.id}/links/friends",
                     :related => "http://foo.bar.com/#{item.id}/friends",
                     :id => ['1', '2', '3'],
                     :type => 'user'
              end
            end
          end

          it 'renders all the keys' do
            expect(hash.fetch(:data).fetch(:links)).to eq({
              :friends => {
                :self => 'http://foo.bar.com/1/links/friends',
                :related => 'http://foo.bar.com/1/friends',
                :id => ['1', '2', '3'],
                :type => 'user'
              }
            })
          end
        end

        context 'with invalid keys' do
          let(:jsonapi_serializer_class) do
            Class.new(Oat::Serializer) do
              schema do
                type 'users'
                link :friends,
                     :not_a_valid_key => 'value'
              end
            end
          end

          it 'errs' do
            expect{hash}.to raise_error(ArgumentError)
          end
        end
      end
    end

    context 'with a nil entity relationship' do
      let(:manager) { nil }
      let(:user_data) { hash.fetch(:data) }

      it 'excludes the entity from user links' do
        expect(user_data.fetch(:links)).not_to include(:manager)
      end

      it 'excludes the entity from the included collection' do
        expect(hash.fetch(:included)).not_to include(:managers)
      end
    end

    context 'with a nil entities relationship' do
      let(:user) { user_class.new('Ismael', 35, 1, nil, manager) }
      let(:user_data) { hash.fetch(:data) }

      it 'excludes the entity from user links' do
        expect(user_data.fetch(:links)).not_to include(:friends)
      end

      it 'excludes the entity from the included collection' do
        expect(hash.fetch(:included)).not_to include(:friends)
      end
    end

    context 'when an empty entities relationship' do
      let(:user) { user_class.new('Ismael', 35, 1, [], manager) }
      let(:user_data) { hash.fetch(:data) }

      it 'excludes the entity from user links' do
        expect(user_data.fetch(:links)).not_to include(:friends)
      end

      it 'excludes the entity from the included collection' do
        expect(hash.fetch(:included)).not_to include(:friends)
      end
    end

    context 'with an entity collection' do
      let(:serializer_collection_class) do
        USER_SERIALIZER = jsonapi_serializer_class unless defined?(USER_SERIALIZER)
        Class.new(Oat::Serializer) do
          schema do
            type 'users'
            collection :users, item, USER_SERIALIZER
          end
        end
      end

      let(:collection_serializer){
        serializer_collection_class.new(
          [user,friend],
          {:name => 'some_controller'},
          Oat::Adapters::JsonAPI
        )
      }
      let(:collection_hash) { collection_serializer.to_hash }

      context 'top level' do
        subject(:users){ collection_hash.fetch(:data) }
        its(:size) { should eq(2) }

        it 'contains the correct first user properties' do
          expect(users[0]).to include(
            :id => user.id,
            :type => :users,
            :name => user.name,
            :age => user.age,
            :controller_name => 'some_controller',
            :message_from_above => nil
          )
        end

        it 'contains the correct second user properties' do
          expect(users[1]).to include(
            :id => friend.id,
            :type => :users,
            :name => friend.name,
            :age => friend.age,
            :controller_name => 'some_controller',
            :message_from_above => nil
          )
        end

        it 'contains the correct user links' do
          expect(users.first.fetch(:links)).to include(
            :self => "http://foo.bar.com/#{user.id}",
            :empty => nil,
            # these links are added by embedding entities
            :manager => {id: manager.id.to_s, type: 'managers'},
            :friends => {type: 'users', id: [friend.id.to_s]}
          )
        end

        context 'sub entity' do
          subject(:included_managers){ collection_hash.fetch(:included).select {|item| item[:type] == :managers} }

          it 'does not duplicate an entity that is associated with multiple objects' do
            expect(included_managers.size).to eq(1)
          end

          it 'contains the correct properties and links' do
            expect(included_managers.first).to include(
              :id => manager.id,
              :type => :managers,
              :name => manager.name,
              :age => manager.age,
              :links => { :self => "http://foo.bar.com/#{manager.id}" }
            )
          end
        end
      end
    end

    context 'link_template' do
      let(:jsonapi_serializer_class) do
        Class.new(Oat::Serializer) do
          schema do
            type 'users'
            link 'user.managers', :related => 'http://foo.bar.com/{user.id}/managers', :templated => true
            link 'user.friends',  :related => 'http://foo.bar.com/{user.id}/friends', :templated => true
          end
        end
      end

      it 'renders them top level' do
        expect(hash.fetch(:links)).to eq({
          'user.managers' => 'http://foo.bar.com/{user.id}/managers',
          'user.friends'  => 'http://foo.bar.com/{user.id}/friends'
        })
      end

      it 'doesn\'t render them as links on the resource' do
        expect(hash.fetch(:data)).to_not have_key(:links)
      end
    end
  end
end
