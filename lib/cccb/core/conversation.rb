require 'securerandom'

class CCCB::Conversation < OpenStruct
  def initialize(**args)
    @history = [ [ :creation, Time.now ] ]
    super
    self.hook_name ||= :conversation_generic
    self.cleanup_hook ||= :"#{self.hook_name}__cleanup"
  end

  def process(text)
    @history << [ :in, Time.now, text ]
    schedule_hook self.hook_name, self, text
  end

  def reply(text)
    @history << [ :out, Time.now, text ]
    self.message.reply text
    self.message.send_reply
  end

  def inactive?(timeout = 60)
    Time.now - @history.last[1] > timeout
  end

  def end
    run_hooks self.cleanup_hook, self
  end
end

module CCCB::Core::Conversations
  extend Module::Requirements
  needs :api_core, :commands, :events

  def get_conversation(message)
    conversations.lock.synchronize do 
      cursor = conversations.store
      return unless cursor.include? message.network
      cursor = cursor[message.network]
      return unless cursor.include? message.user
      cursor = cursor[message.user]
      return unless cursor.include? message.replyto
      cursor[message.replyto]
    end
  end

  def module_load
    default_setting 300, 'options', 'conversation_timeout'
    conversations.lock = Mutex.new
    conversations.store ||= {}

    #@doc 
    # Begins a test conversation with the bot.
    add_command :conversation, %w{ conversation test } do |message, args|
      conversation = api('conversation.new', __message: message)
      message.reply conversation
    end

    #@doc
    # An example conversation responder
    add_hook :conversation, :conversation_generic do |conversation, text|
      conversation.reply "<in conversation #{conversation}>: #{text}"
    end

    #@doc
    # Feeds conversation messages to the bot
    # A conversation in this case is a two-way session with the bot that
    # has its own state and history.
    add_request :conversation, /^(.*)$/ do |match, message|
      next if message.actioned?
      conv = get_conversation(message)
      next unless conv
      conv.process(match[1])
      nil
    end

    #@doc
    # Creates a new conversation with the user who created the calling request
    register_api_method :conversation, :new do |**args|
      message = args[:__message]
      cursor = (conversations.store[message.network] ||= {})
      cursor = (cursor[message.user] ||= {})
      cursor[message.replyto] ||= CCCB::Conversation.new( message: message )
    end

    #@doc
    # Ends a conversation
    register_api_method :conversation, :end do |**args|
      conversation = get_conversation(args[:__message])
      next unless conversation
      conversation.end
    end

    add_event frequency: 10, 
      hook: :conversation_cleanup, 
      name: 'Clean up conversations', 
      recurrs: true,
      start_time: Time.now + 10

    #@doc
    # Times out conversations when they have not been updated in a set time
    add_hook :conversation, :conversation_cleanup  do
      conversations.lock.synchronize do 

        detail2 conversations.store
        conversations.store.each do |network, users|
          timeout = network.get_setting('options', 'conversation_timeout').to_i
          users.each do |user, contexts|
            contexts.each do |context, conversation|
              if conversation.inactive?(timeout)
                conversation.reply("Conversation terminated")
                conversations.store[network][user].delete(context)
              end
            end
            users.delete(user) if contexts.empty?
          end
          conversations.store.delete(network) if users.empty?
        end

      end

    end
  end
end
