# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  before do
    allow(UserStateTransitionSegmentService)
      .to receive(:call).and_return(true)
    allow(UserPullRequestSegmentUpdaterService)
      .to receive(:call).and_return(true)
  end

  describe '#register' do
    before { user.register }

    context 'user is created but has not agreed to terms' do
      let(:user) { FactoryBot.create(:user, :new) }

      it 'disallows the user to enter the registered state', :vcr do
        expect(user.state).to eq('new')
      end

      it 'applies the correct errors to the user object', :vcr do
        expect(user.errors.messages[:terms_acceptance].first)
          .to eq('must be accepted')
      end
    end

    context 'user has no email' do
      let(:user) { FactoryBot.create(:user, :no_email, state: 'new') }

      it 'disallows the user to enter the registered state', :vcr do
        expect(user.state).to eq('new')
      end

      it 'applies the correct errors to the user object', :vcr do
        expect(user.errors.messages[:email].first).to eq("can't be blank")
      end
    end

    context 'user has neither an email nor an agreement' do
      let(:user) { FactoryBot.create(:user, :new, :no_email) }

      it 'disallows the user to enter the registered state', :vcr do
        expect(user.state).to eq('new')
      end

      it 'adds the correct errors to the user object', :vcr do
        expect(user.errors.messages[:email].first).to eq("can't be blank")
        expect(user.errors.messages[:terms_acceptance].first)
          .to eq('must be accepted')
      end
    end

    context 'an unregistered user has an email and has agreed to terms' do
      let(:user) { FactoryBot.create(:user, state: 'new') }

      it 'allows the user to enter the registered state', :vcr do
        expect(user.state).to eq('registered')
      end

      it 'persists the registered state', :vcr do
        user.reload
        expect(user.state).to eq('registered')
      end
    end
  end

  describe '#wait' do
    context 'registered user has 4 open prs' do
      let(:user) { FactoryBot.create(:user) }

      before do
        allow(user).to receive(:eligible_pull_requests_count).and_return(4)
        user.wait
      end

      it 'allows the user to enter the waiting state', :vcr do
        expect(user.state).to eq('waiting')
      end

      it 'persists the waiting state', :vcr do
        user.reload
        expect(user.state).to eq('waiting')
      end
    end

    context 'registered user has less than 4 open prs' do
      let(:user) { FactoryBot.create(:user) }

      before do
        allow(user).to receive(:eligible_pull_requests_count).and_return(3)
        user.wait
      end

      it 'disallows the user to enter the waiting state', :vcr do
        expect(user.state).to eq('registered')
      end

      it 'adds the correct errors to the user', :vcr do
        expect(user.errors.messages[:sufficient_eligible_prs?].first)
          .to include('user does not have sufficient eligible prs')
      end
    end
  end

  describe '#complete' do
    let(:user) { FactoryBot.create(:user, :waiting) }

    context 'the user has 4 eligible PRs and has been waiting for 7 days' do
      before do
        allow(user).to receive(:eligible_pull_requests_count).and_return(4)
        allow(user).to receive(:waiting_since).and_return(Date.today - 8)
        user.complete
      end

      it 'allows the user to enter the completed state', :vcr do
        expect(user.state).to eq('completed')
      end

      it 'persists the completed state', :vcr do
        user.reload
        expect(user.state).to eq('completed')
      end
    end

    context 'the user has 4 eligible PRs but has not been waiting for 7 days' do
      before do
        allow(user).to receive(:eligible_pull_requests_count).and_return(4)
        allow(user).to receive(:waiting_since).and_return(Date.today - 2)

        user.complete
      end

      it 'disallows the user to enter the completed state', :vcr do
        expect(user.state).to eq('waiting')
      end

      it 'adds the correct errors to user', :vcr do
        expect(user.errors.messages[:won_hacktoberfest?].first)
          .to include('user has not met all winning conditions')
      end
    end

    context 'the user has been waiting for 7 days but has less than 4 eligible prs' do
      before do
        allow(user).to receive(:eligible_pull_requests_count).and_return(3)
        allow(user).to receive(:waiting_since).and_return(Date.today - 8)

        user.complete
      end

      it 'disallows the user to enter the completed state', :vcr do
        expect(user.state).to eq('waiting')
      end

      it 'adds the correct errors to user', :vcr do
        expect(user.errors.messages[:won_hacktoberfest?].first)
          .to include('user has not met all winning conditions')
      end
    end

    context 'the user neither 4 eligible PRs nor has been waiting for 7 days' do
      before do
        allow(user).to receive(:eligible_pull_requests_count).and_return(3)
        allow(user).to receive(:waiting_since).and_return(Date.today - 2)

        user.complete
      end

      it 'disallows the user to enter the completed state', :vcr do
        expect(user.state).to eq('waiting')
      end

      it 'adds the correct errors to user', :vcr do
        expect(user.errors.messages[:won_hacktoberfest?].first)
          .to include('user has not met all winning conditions')
      end
    end
  end

  describe '#ineligible' do
    context 'waiting user has dropped below 4 prs' do
      let(:user) { FactoryBot.create(:user, :waiting) }

      before do
        allow(user).to receive(:eligible_pull_requests_count).and_return(3)
        user.ineligible
      end

      it 'transitions the user back to the registered state', :vcr do
        expect(user.state).to eq('registered')
      end

      it 'persists the registered state', :vcr do
        user.reload
        expect(user.state).to eq('registered')
      end
    end
  end

  describe '#incomplete' do
    context 'the user is in the complete state' do
      let(:user) { FactoryBot.create(:user, :completed) }

      before do
        user.incomplete
      end

      it 'disallows the user to enter the incomplete state' do
        expect(user.state).to eq('completed')
      end

      it 'adds the correct errors to the user' do
        expect(user.errors.messages[:state].first)
          .to include('cannot transition via "incomplete"')
      end
    end

    context 'hacktoberfest has not yet ended' do
      let(:user) { FactoryBot.create(:user) }

      before do
        allow(user).to receive(:hacktoberfest_ended?).and_return(false)
        user.incomplete
      end

      it 'disallows the user to enter the incompleted state', :vcr do
        expect(user.state).to eq('registered')
      end

      it 'adds the correct errors to the user', :vcr do
        expect(user.errors.messages[:hacktoberfest_ended?].first)
          .to include('hacktoberfest has not yet ended')
      end
    end

    context 'hacktoberfest has ended', :vcr do
      let(:user) { FactoryBot.create(:user) }

      before do
        allow(user).to receive(:hacktoberfest_ended?).and_return(true)
        user.incomplete
      end

      it 'transitions the user to the incomplete state', :vcr do
        expect(user.state).to eq('incompleted')
      end

      it 'persists the registered state', :vcr do
        user.reload
        expect(user.state).to eq('incompleted')
      end
    end
  end
end
