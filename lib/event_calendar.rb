module EventCalendar
  
  def self.included(base)
    base.send :extend, ClassMethods
  end

  module ClassMethods

    def has_event_calendar(options={})
      cattr_accessor :start_at_field, :end_at_field 
      self.start_at_field = ( options[:start_at_field] ||= :start_at).to_s
      self.end_at_field   = ( options[:end_at_field]   ||= :end_at  ).to_s
      alias_attribute :start_at, start_at_field unless start_at_field == 'start_at'
      alias_attribute :end_at,   end_at_field   unless end_at_field   == 'end_at'
      before_save :adjust_all_day_dates
      send :include, InstanceMethods
    end

    # For the given month, find the start and end dates
    # Find all the events within this range, and create event strips for them
    def event_strips_for_month(shown_date, first_day_of_week=0, find_options = {})
      if first_day_of_week.is_a?(Hash)
        find_options.merge!(first_day_of_week)
        first_day_of_week =  0
      end
      strip_start, strip_end = get_start_and_end_dates(shown_date, first_day_of_week)
      events = events_for_date_range(strip_start, strip_end, find_options)
      event_strips = create_event_strips(strip_start, strip_end, events)
      event_strips
    end
=begin
    def schedule_strips_for_month(shown_date, first_day_of_week=0, find_options = {})
      if first_day_of_week.is_a?(Hash)
        find_options.merge!(first_day_of_week)
        first_day_of_week =  0
      end
      strip_start, strip_end = get_start_and_end_dates(shown_date, first_day_of_week)
      schedules = schedules_for_date_range(strip_start, strip_end, find_options)
      schedule_strips = create_schedule_strips(strip_start, strip_end, schedules)
      schedule_strips
    end
=end
    def event_strips_for_range(strip_start, strip_end, find_options = {})
      events = events_for_date_range(strip_start, strip_end, find_options)
      event_strips = create_event_strips(strip_start, strip_end, events)
      event_strips
    end
    
    # Expand start and end dates to show the previous month and next month's days,
    # that overlap with the shown months display
    def get_start_and_end_dates(shown_date, first_day_of_week=0)
      # start with the first day of the given month
      start_of_month = Date.civil(shown_date.year, shown_date.month, 1)
      # the end of last month
      strip_start = beginning_of_week(start_of_month, first_day_of_week)
      # the beginning of next month, unless this month ended evenly on the last day of the week
      if start_of_month.next_month == beginning_of_week(start_of_month.next_month, first_day_of_week)
        # last day of the month is also the last day of the week
        strip_end = start_of_month.next_month
      else
        # add the extra days from next month
        strip_end = beginning_of_week(start_of_month.next_month + 7, first_day_of_week)
      end
      [strip_start, strip_end]
    end
    
    # Get the events overlapping the given start and end dates
    def events_for_date_range(start_d, end_d, with_recurring = false, find_options = {})
      if !with_recurring
        base_events = self.scoped(find_options).find(
          :all,
          :conditions => [ "(? <= #{self.quoted_table_name}.#{self.end_at_field}) AND (#{self.quoted_table_name}.#{self.start_at_field}< ?)", start_d.to_time, end_d.to_time ],
          :order => "#{self.quoted_table_name}.#{self.start_at_field} ASC"
        )
      else
        base_events = []
      end
      if with_recurring
        recurring_events = self.scoped(find_options).find(
          :all,
          :conditions => [ "repeating=1" ],
#          :conditions => [ "occurrences IS NOT NULL" ],
          :order => "#{self.quoted_table_name}.#{self.start_at_field} ASC"
        )
        recurring_events_in_date_range = Array.new
        recurring_events.each_with_index do |recurring_event, index|
=begin
          if !recurring_event.occurrences.to_s.empty?
            # remove it from base events if we have occurrences
            base_events.delete(recurring_event)
          end
=end
          
          recurring_event.occurrences.occurrences(end_d.end_of_day).each do |o|
            o_start = o.to_time
            o_end = o_start + recurring_event.occurrences.duration
            if !recurring_event.occurrences.exception_times.include?(start_d+1.second) and o_start <= end_d and o_end >= start_d
              e = recurring_event.dup
              e.children << recurring_event.children.dup
              e.start_at = o_start
              e.end_at = o_end
              e.base_event_id = recurring_event.id
              #recurring_events_in_date_range << e
              
              occurring_days = []
              e.start_at.to_date.upto(e.end_at.to_date) do |day|
                if !recurring_event.occurrences.exception_times.include?(day.to_time+1.second)
                  occurring_days << day
                end
              end
              #logger.info "----- #{recurring_event.id} / occurring_days = #{occurring_days.inspect}"
              if occurring_days.size-1 != (e.end_at.to_date - e.start_at.to_date) and !occurring_days.empty?
                #logger.info " ---- occurring_days.size !="
                e.start_at = occurring_days.first.to_datetime
                e.end_at = e.start_at
                for day in occurring_days do
                  #logger.info "day #{day.inspect}"
                  if day != e.end_at.to_date
                    if day == e.end_at.to_date.tomorrow
                      #logger.info "tomorrow (#{day.to_datetime.inspect})"
                      e.end_at = day.to_datetime
                    else
                      recurring_events_in_date_range << e
                      e = recurring_event.dup
                      e.children << recurring_event.children.dup
                      e.base_event_id = recurring_event.id
                      e.start_at = day.to_time
                      e.end_at = e.start_at
                    end
                  end
                end
              end
              if !occurring_days.empty?
                recurring_events_in_date_range << e
              end
            end
          end
        end
=begin
          # if this recurring event occurs during the date range
          if recurring_event.occurrences.occurs_between?(start_d.to_time, end_d.to_time) or recurring_event.occurrences.occurring_at?(start_d.to_time)
            logger.info "recurring_event #{recurring_event.id}"
            recurring_event.base_event_id = recurring_event.id
#            recurring_events_in_date_range << recurring_event

            # add recurring events
            recurring_event.occurrences.occurrences(end_d.to_datetime+1.day).each do |o|
              logger.info "recurring_event #{recurring_event.id} / o = #{o.inspect}"
              if 1 == 1 or o.to_date >= start_d# and o != recurring_event.start_at
                e = recurring_event.dup
                e.start_at = o
                e.end_at = o + recurring_event.occurrences.duration
                e.base_event_id = recurring_event.id
                e.children << recurring_event.children.collect { |child| child.clone }
                
                occurring_days = []
#                occurring_days << e.start_at.to_date
                e.start_at.to_date.upto(e.end_at.to_date) do |day|
                  if recurring_event.occurrences.exception_times.include?(day.to_time+1.second)
#                    e.end_at = occurring_days.last
                  else
                    occurring_days << day
                  end
                end
                logger.info "----- #{recurring_event.id} / occurring_days = #{occurring_days.inspect}"
                if occurring_days.size-1 != (e.end_at.to_date - e.start_at.to_date) and !occurring_days.empty?
                  logger.info " ---- occurring_days.size !="
                  e.start_at = occurring_days.first.to_datetime
                  e.end_at = e.start_at
                  for day in occurring_days do
                    logger.info "day #{day.inspect}"
                    if day != e.end_at.to_date
                      if day == e.end_at.to_date.tomorrow
                        logger.info "tomorrow (#{day.to_datetime.inspect})"
                        e.end_at = day.to_datetime
                      else
                        recurring_events_in_date_range << e
                        e = recurring_event.dup
                        e.start_at = day.to_datetime
                        e.end_at = e.start_at
                        e.base_event_id = recurring_event.id
                        e.children << recurring_event.children.collect { |child| child.clone }
                      end
                    end
                  end
                end
                
                logger.info "e = #{e.inspect}"
                if !occurring_days.empty?
                  recurring_events_in_date_range << e
                end
              end
            end
          end
        end
=end
        base_events << recurring_events_in_date_range
      end
      base_events.flatten
    end

    # Create the various strips that show events.
    def create_event_strips(strip_start, strip_end, events)
      # create an inital event strip, with a nil entry for every day of the displayed days
      event_strips = [[nil] * (strip_end - strip_start + 1)]

      events.each do |event|
#        logger.info "----- event loop -----"
#        logger.info "event_strips = #{event_strips.inspect}"
        cur_date = event.start_at
        end_date = event.end_at
        cur_date, end_date = event.clip_range(strip_start, strip_end)
        start_range = (cur_date - strip_start).to_i
        end_range = (end_date - strip_start).to_i
#        logger.info "event = #{event.inspect} / cur_date: #{cur_date.inspect} / end_date: #{end_date.inspect} / start_range: #{start_range} / end_range: #{end_range}"
      
        # make sure the event is within our viewing range
        if (start_range <= end_range) and (end_range >= 0)
          range = start_range..end_range
#          logger.info "range: #{range.inspect}"

          open_strip = space_in_current_strips?(event_strips, range)
#          logger.info "open strip: #{open_strip}"
          
          if open_strip.nil?
#            logger.info "no strips open, make a new one"
            # no strips open, make a new one
            new_strip = [nil] * (strip_end - strip_start + 1)
            range.each { |r|
              new_strip[r] = event
            }
#            logger.info "new_strip = #{new_strip.inspect}"
            event_strips << new_strip
          else
            # found an open strip, add this event to it
            range.each {|r| open_strip[r] = event}
#            logger.info "found an open strip, add this event to it / #{open_strip.inspect}"
          end
        end
      end
      event_strips
    end
    
    def space_in_current_strips?(event_strips, range)
      open_strip = nil
      for strip in event_strips
        strip_is_open = true
        range.each do |r|
          # overlapping events on this strip
          if !strip[r].nil?
            strip_is_open = false
            break
          end
        end

        if strip_is_open
          open_strip = strip
          break
        end
      end
      open_strip
    end
    
    def days_between(first, second)
      if first > second
        second + (7 - first)
      else
        second - first
      end
    end

    def beginning_of_week(date, start = 0)
      days_to_beg = days_between(start, date.wday)
      date - days_to_beg
    end
    
  end
  
  # Instance Methods
  # Override in your model as needed
  module InstanceMethods
    def year
      date.year
    end
  
    def month
      date.month
    end
 
    def day
      date.day
    end
    
    def all_day
      self[:all_day]
    end
    
    def color
      self[:color] || '#96AF41'
    end
  
    def days
      end_at.to_date - start_at.to_date
    end
  
    # start_d - start of the month, or start of the week
    # end_d - end of the month, or end of the week
    def clip_range(start_d, end_d)
      # make sure we are comparing date objects to date objects,
      # otherwise timezones can cause problems
      start_at_d = start_at.to_date
      end_at_d = end_at.to_date
      # Clip start date, make sure it also ends on or after the start range
      if (start_at_d < start_d and end_at_d >= start_d)
        clipped_start = start_d
      else
        clipped_start = start_at_d
      end
    
      # Clip end date
      if (end_at_d > end_d)
        clipped_end = end_d
      else
        clipped_end = end_at_d
      end
      [clipped_start.to_date, clipped_end]
    end

    def adjust_all_day_dates
      if self.all_day
        self.start_at = self.start_at.beginning_of_day

        if self.end_at
          if self.is_a?(Swap)
#            self.end_at = self.end_at.end_of_day - 1.day
            self.end_at = self.end_at.beginning_of_day
          else
            self.end_at = self.end_at.beginning_of_day + 1.day - 1.second
          end
        else
          self.end_at = self.start_at + 1.day - 1.second
        end
      end
      #UTCOMMENT
=begin
      if self.is_a?(SchedulePeriod) or self.is_a?(Swap)
        self.start_at = Time.at(self.start_at).utc
        self.end_at = Time.at(self.end_at).utc
      end
=end
    end

  end
end

require 'event_calendar/railtie' if defined?(::Rails::Railtie)