require 'spec_helper'
require 'money-rails/test_helpers'
module ManageIQ::Consumption
  describe ShowbackRate do
    before(:each) do
      ShowbackUsageType.seed
    end
    describe 'model validations' do
      let(:showback_rate) { FactoryGirl.build(:showback_rate) }

      it 'has a valid factory' do
        expect(showback_rate).to be_valid
      end

      it 'has a tier after create' do
        sr = FactoryGirl.create(:showback_rate)
        expect(sr.showback_tiers.count).to eq(1)
      end

      it 'returns name as category + dimension' do
        category = showback_rate.category
        dimension = showback_rate.dimension
        measure = showback_rate.measure
        expect(showback_rate.name).to eq("#{category}:#{measure}:#{dimension}")
      end

      it 'is not valid with a nil calculation' do
        showback_rate.calculation = nil
        showback_rate.valid?
        expect(showback_rate.errors.details[:calculation]).to include(:error=>:blank)
      end

      it 'calculation is valid when included in VALID_RATE_CALCULATIONS' do
        calculations = %w(occurrence duration quantity)
        expect(ManageIQ::Consumption::ShowbackRate::VALID_RATE_CALCULATIONS).to eq(calculations)
        calculations.each do |calc|
          showback_rate.calculation = calc
          expect(showback_rate).to be_valid
        end
      end

      it 'calculation is not valid if it is not in VALID_RATE_CALCULATIONS' do
        showback_rate.calculation = 'ERROR'
        expect(showback_rate).not_to be_valid
        expect(showback_rate.errors.details[:calculation]). to include(:error => :inclusion, :value => 'ERROR')
      end

      it 'is not valid with a nil category' do
        showback_rate.category = nil
        showback_rate.valid?
        expect(showback_rate.errors.details[:category]).to include(:error=>:blank)
      end

      it 'is not valid with a nil dimension' do
        showback_rate.dimension = nil
        showback_rate.valid?
        expect(showback_rate.errors.details[:dimension]).to include(:error=>:blank)
      end

      it 'is valid with a nil concept' do
        showback_rate.concept = nil
        showback_rate.valid?
        expect(showback_rate).to be_valid
      end

      it '#measure is valid with a non empty string' do
        showback_rate.measure = 'Hz'
        showback_rate.valid?
        expect(showback_rate).to be_valid
      end

      it '#measure is not valid when nil' do
        showback_rate.measure = nil
        showback_rate.valid?
        expect(showback_rate.errors.details[:measure]).to include(:error => :blank)
      end

      it 'is valid with a JSON screener' do
        showback_rate.screener = JSON.generate('tag' => { 'environment' => ['test'] })
        showback_rate.valid?
        expect(showback_rate).to be_valid
      end

      pending 'is not valid with a wronly formatted screener' do
        showback_rate.screener = JSON.generate('tag' => { 'environment' => ['test'] })
        showback_rate.valid?
        expect(showback_rate).not_to be_valid
      end

      it 'is not valid with a nil screener' do
        showback_rate.screener = nil
        showback_rate.valid?
        expect(showback_rate.errors.details[:screener]).to include(:error => :exclusion, :value => nil)
      end
    end

    describe 'when the event lasts for the full month and the rates too' do
      let(:fixed_rate)    { Money.new(11) }
      let(:variable_rate) { Money.new(7) }
      let(:showback_rate) { FactoryGirl.create(:showback_rate, :CPU_number) }
      let(:showback_tier) do
        tier = showback_rate.showback_tiers.first
        tier.fixed_rate    = fixed_rate
        tier.variable_rate = variable_rate
        tier.variable_rate_per_unit = "cores"
        tier.save
        tier
      end
      let(:showback_event_fm) { FactoryGirl.create(:showback_event, :full_month, :with_vm_data) }

      context 'empty #context, default rate per_time and per_unit' do
        it 'should charge an event by occurrence when event exists' do
          showback_tier
          showback_event_fm.reload
          showback_rate.calculation = 'occurrence'
          expect(showback_rate.rate(showback_event_fm)).to eq(fixed_rate + variable_rate)
        end

        it 'should charge an event by occurrence only the fixed rate when value is nil' do
          showback_tier
          showback_event_fm.reload
          showback_rate.calculation = 'occurrence'
          showback_event_fm.data = {} # There is no data for this rate in the event
          expect(showback_rate.rate(showback_event_fm)).to eq(fixed_rate)
        end

        it 'should charge an event by duration' do
          showback_tier
          showback_event_fm.reload
          showback_rate.calculation = 'duration'
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 2))
        end

        it 'should charge an event by quantity' do
          showback_tier
          showback_event_fm.reload
          showback_rate.calculation = 'quantity'
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 2))
        end
      end

      context 'minimum step' do
        let(:fixed_rate)    { Money.new(11) }
        let(:variable_rate) { Money.new(7) }
        let(:showback_rate) { FactoryGirl.create(:showback_rate, :MEM_max_mem) }
        let(:showback_tier) do
          tier = showback_rate.showback_tiers.first
          tier.fixed_rate    = fixed_rate
          tier.variable_rate = variable_rate
          tier.variable_rate_per_unit = "MiB"
          tier.save
          tier
        end
        let(:showback_event_fm) { FactoryGirl.create(:showback_event, :full_month, :with_vm_data) }
        let(:showback_event_hm) { FactoryGirl.create(:showback_event, :first_half_month, :with_vm_data) }

        it 'nil step should behave like no step' do
          showback_event_fm.reload
          showback_tier.step_unit = nil
          showback_tier.step_value = nil
          showback_tier.step_time_value = nil
          showback_tier.step_time_unit = nil
          showback_tier.save
          showback_rate.calculation = 'duration'
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 2048))
        end

        it 'basic unit step should behave like no step' do
          showback_event_fm.reload
          showback_tier.step_unit = 'b'
          showback_tier.step_value = 1
          showback_tier.step_time_value = nil
          showback_tier.step_time_unit = nil
          showback_tier.save
          showback_rate.calculation = 'duration'
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 2048))
        end

        it 'when input is 0 it works' do
          showback_tier.step_unit = 'b'
          showback_tier.step_value = 1
          showback_tier.step_time_value = nil
          showback_tier.step_time_unit = nil
          showback_rate.calculation = 'duration'
          showback_event_fm.data["MEM"]["max_mem"][0] = 0
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11))
        end

        it 'should work if step unit is a subunit of the tier' do
          showback_event_fm.reload
          showback_tier.step_unit = 'Gib'
          showback_tier.step_value = 1
          showback_tier.step_time_value = nil
          showback_tier.step_time_unit = nil
          showback_rate.calculation = 'duration'
          showback_tier.save
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 2048))

          showback_tier.step_value = 4
          showback_tier.step_unit = 'Gib'
          showback_tier.save
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 4096))

          # Modify the input data so the data is not a multiple
          showback_event_fm.data["MEM"]["max_mem"][0] = 501
          showback_event_fm.data["MEM"]["max_mem"][1] = 'MiB'

          showback_tier.step_unit = 'MiB'
          showback_tier.step_value = 384
          showback_tier.save
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 384 * 2))
        end

        pending 'step time moves half_month to full_month' do
          showback_tier.step_unit = 'b'
          showback_tier.step_value = 1
          showback_tier.step_time_value = 1
          showback_tier.step_time_unit = 'month'
          showback_rate.calculation = 'duration'
          expect(showback_rate.rate(showback_event_hm)).to eq(showback_rate.rate(showback_event_fm))
        end

        pending 'step is not a subunit of the tier' do
          # Rate is using Vm:CPU:Number
          showback_tier.step_unit = 'cores'
          showback_tier.step_value = 1
          showback_tier.step_time_value = nil
          showback_tier.step_time_unit = nil
          showback_rate.calculation = 'duration'
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + 7 * 2))
        end

        pending 'step is higher than the tier'
      end

      context 'empty #context, modified per_time' do
        it 'should charge an event by occurrence' do
          showback_event_fm.reload
          showback_rate.calculation = 'occurrence'
          showback_tier.fixed_rate_per_time    = 'daily'
          showback_tier.variable_rate_per_time = 'daily'
          showback_tier.save
          days_in_month = Time.days_in_month(Time.current.month)
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(days_in_month * (11 + 7)))
        end

        it 'should charge an event by duration' do
          showback_tier
          showback_event_fm.reload
          showback_rate.calculation = 'duration'
          showback_tier.fixed_rate_per_time    = 'daily'
          showback_tier.variable_rate_per_time = 'daily'
          showback_tier.save
          days_in_month = Time.days_in_month(Time.current.month)
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(days_in_month * (11 + 7 * 2)))
        end

        it 'should charge an event by quantity' do
          showback_event_fm.reload
          showback_rate.calculation = 'quantity'
          showback_tier.fixed_rate_per_time    = 'daily'
          showback_tier.variable_rate_per_time = 'daily'
          showback_tier.save
          days_in_month = Time.days_in_month(Time.current.month)
          # Fixed is 11 per day, variable is 7 per CPU, event has average of 2 CPU
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new((days_in_month * 11) + (7 * 2)))
        end
      end

      context 'empty context, modified per unit' do
        it 'should charge an event by duration' do
          showback_event_fm.reload
          showback_rate.calculation = 'duration'
          showback_rate.dimension = 'max_mem'
          showback_rate.measure = 'MEM'
          showback_tier.variable_rate_per_unit = 'b'
          showback_tier.save
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + (2048 * 1024 * 1024 * 7)))
          showback_tier.variable_rate_per_unit = 'Kib'
          showback_tier.save
          expect(showback_rate.rate(showback_event_fm)).to eq(Money.new(11 + (2048 * 1024 * 7)))
        end

        pending 'should charge an event by quantity'
      end

      context 'tiered on input value' do
        pending 'it should charge an event by occurrence'
        pending 'it should charge an event by duration'
        pending 'it should charge an event by quantity'
      end

      context 'tiered on non-input value in #context' do
        pending 'it should charge an event by occurrence'
        pending 'it should charge an event by duration'
        pending 'it should charge an event by quantity'
      end
    end

    describe 'more than 1  tier in the rate' do
      let(:fixed_rate)    { Money.new(11) }
      let(:variable_rate) { Money.new(7) }
      let(:showback_rate) { FactoryGirl.create(:showback_rate, :CPU_number, :calculation => 'quantity') }
      let(:showback_event_hm) { FactoryGirl.create(:showback_event, :first_half_month, :with_vm_data) }
      let(:showback_tier) do
        tier = showback_rate.showback_tiers.first
        tier.fixed_rate = fixed_rate
        tier.tier_end_value = 3.0
        tier.step_unit = 'cores'
        tier.step_value = 1
        tier.variable_rate = variable_rate
        tier.variable_rate_per_unit = "cores"
        tier.save
        tier
      end
      let(:showback_tier_second) do
        FactoryGirl.create(:showback_tier,
                           :showback_rate          => showback_rate,
                           :tier_start_value       => 3.0,
                           :tier_end_value         => Float::INFINITY,
                           :step_value             => 1,
                           :step_unit              => 'cores',
                           :fixed_rate             => Money.new(15),
                           :variable_rate          => Money.new(10),
                           :variable_rate_per_unit => "cores")
      end
      context 'use only a single tier' do
        it 'should charge an event by quantity with 1 tier with tiers_use_full_value' do
          showback_event_hm.reload
          showback_tier
          showback_tier_second
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(11 + 7 * 2))
          showback_event_hm.data['CPU']['number'][0] = 4.0
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(15 + 10 * 4))
        end
        it 'should charge an event by quantity with 1 tier with not tiers_use_full_value' do
          showback_event_hm.reload
          showback_tier
          showback_tier_second
          showback_rate.tiers_use_full_value = false
          showback_rate.step_variable = 'cores'
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(11 + 7 * (2 - 0)))
          showback_event_hm.data['CPU']['number'][0] = 4.0
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(15 + (10 * (4 - 3.0))))
        end
      end

      context 'with all tiers' do
        it 'should charge an event by quantity with 2 tiers with tiers_use_full_value' do
          showback_event_hm.reload
          showback_tier
          showback_tier_second
          showback_rate.uses_single_tier = false
          showback_event_hm.data['CPU']['number'][0] = 4.0
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(11 + 7 * 4) + Money.new(15 + 10 * 4))
        end

        it 'should charge an event by quantity with 2 tiers with not tiers_use_full_value' do
          showback_event_hm.reload
          showback_tier
          showback_tier_second
          showback_rate.uses_single_tier = false
          showback_rate.tiers_use_full_value = false
          showback_rate.step_variable = 'cores'
          showback_event_hm.data['CPU']['number'][0] = 4.0
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(11 + 7 * (4 - 0)) + Money.new(15 + 10 * (4 - 3.0)))
        end
      end
    end
    describe 'event lasts the first 15 days and the rate is monthly' do
      let(:fixed_rate)    { Money.new(11) }
      let(:variable_rate) { Money.new(7) }
      let(:showback_rate) { FactoryGirl.create(:showback_rate, :CPU_number) }
      let(:showback_event_hm) { FactoryGirl.create(:showback_event, :first_half_month, :with_vm_data) }
      let(:proration)         { showback_event_hm.time_span.to_f / showback_event_hm.month_duration }
      let(:showback_tier) do
        tier = showback_rate.showback_tiers.first
        tier.fixed_rate    = fixed_rate
        tier.variable_rate = variable_rate
        tier.variable_rate_per_unit = "cores"
        tier.save
        tier
      end

      context 'empty #context' do
        it 'should charge an event by occurrence' do
          showback_tier
          showback_rate.calculation = 'occurrence'
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(11) + Money.new(7))
        end

        it 'should charge an event by duration' do
          showback_tier
          showback_event_hm.reload
          showback_rate.calculation = 'duration'
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(11 + 7 * 2) * proration)
        end

        it 'should charge an event by quantity' do
          showback_event_hm.reload
          showback_tier
          showback_rate.calculation = 'quantity'
          # Fixed is 11 per day, variable is 7 per CPU, event has 2 CPU
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(11 + 7 * 2))
        end
      end

      context 'empty #context, modified per_time' do
        it 'should charge an event by occurrence' do
          showback_event_hm.reload
          showback_rate.calculation = 'occurrence'
          showback_tier.fixed_rate_per_time = 'daily'
          showback_tier.variable_rate_per_time = 'daily'
          showback_tier.save
          days_in_month = Time.days_in_month(Time.current.month)
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(days_in_month * (11 + 7)))
        end

        it 'should charge an event by duration' do
          showback_event_hm.reload
          showback_rate.calculation = 'duration'
          showback_tier.fixed_rate_per_time    = 'daily'
          showback_tier.variable_rate_per_time = 'daily'
          showback_tier.save
          days_in_month = Time.days_in_month(Time.current.month)
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new(days_in_month * proration * (11 + 7 * 2)))
        end

        it 'should charge an event by quantity' do
          showback_event_hm.reload
          showback_rate.calculation = 'quantity'
          showback_tier.fixed_rate_per_time    = 'daily'
          showback_tier.variable_rate_per_time = 'daily'
          showback_tier.save
          days_in_month = Time.days_in_month(Time.current.month)
          # Fixed is 11 per day, variable is 7 per CPU, event has 2 CPU
          expect(showback_rate.rate(showback_event_hm)).to eq(Money.new((days_in_month * 11) + (7 * 2)))
        end
      end

      context 'tiered on input value' do
        pending 'it should charge an event by occurrence'
        pending 'it should charge an event by duration'
        pending 'it should charge an event by quantity'
      end

      context 'tiered on non-input value in #context' do
        pending 'it should charge an event by occurrence'
        pending 'it should charge an event by duration'
        pending 'it should charge an event by quantity'
      end
    end

    describe 'event lasts 1 day for a weekly rate' do
      pending 'should charge an event by occurrence'
      pending 'should charge an event by duration'
      pending 'should charge an event by quantity'
    end

    describe 'event lasts 1 week for a daily rate' do
      pending 'should charge an event by occurrence'
      pending 'should charge an event by duration'
      pending 'should charge an event by quantity'
    end
  end
end
