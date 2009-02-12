require 'rubygems'
require 'mechanize'
require 'json'
require 'ostruct'
require 'pp'

class FacebookChat
  def initialize(email, pass); @email, @pass = email, pass; end

  def login
    @agent = WWW::Mechanize.new
    @agent.user_agent_alias = 'Windows IE 7'
    f = @agent.get("http://facebook.com/login.php").forms.first
    f.set_fields(:email => @email, :pass => @pass)
    f.submit
    body = @agent.get("http://www.facebook.com/home.php").root.to_html
    
    # parse info out of facebook home page
    @uid = %r{<a href=".+?/profile.php\?id=(\d+)&amp;ref=profile">Profile</a>}.match(body)[1].to_i
    @channel = %r{"channel(\d+)"}.match(body)[1]
    @post_form_id = %r{<input type="hidden" id="post_form_id" name="post_form_id" value="([^"]+)}.match(body)[1]
  end

  def wait_for_messages
    determine_initial_seq_number  unless @seq
   
    begin
      json = parse_json @agent.get(get_message_url(@seq)).body
    end  while json["t"] == "continue"   # no messages yet, keep waiting
    @seq += 1

    json["ms"].select{|m| m['type'] == 'msg'}.map do |msg|
      info = msg.delete 'msg'
      msg['text'] = info['text']
      msg['time'] = Time.at(info['time']/1000)
      OpenStruct.new msg
    end # .reject {|msg| msg.from == @uid }  # get rid of messages from us
  end

  def send_message(uid, text)
    r = @agent.post "http://www.facebook.com/ajax/chat/send.php", 
      'msg_text' => text, 
      'msg_id' => rand(999999999),
      'client_time' => (Time.now.to_f*1000).to_i,
      'to' => uid,
      'post_form_id' => @post_form_id
  end

  def buddy_list
    json = parse_json(@agent.post("http://www.facebook.com/ajax/presence/update.php", 
                        'buddy_list' => 1, 'force_render' => 1, 'post_form_id' => @post_form_id, 'user' => @uid).body)
    json['payload']['buddy_list']['userInfos'].inject({}) do |hash, (uid, info)|
      hash.merge uid => info['name']
    end
  end

  private

  def determine_initial_seq_number
    # -1 will always be a bad seq number so fb will tell us what the correct one is
    json = parse_json @agent.get(get_message_url(-1)).body
    @seq = json["seq"].to_i
  end

  def get_message_url(seq)
    "http://0.channel#{@channel}.facebook.com/x/0/false/p_#{@uid}=#{seq}"
  end
  
  # get rid of initial js junk, like 'for(;;);'
  def parse_json(s)
    JSON.parse s.sub(/^[^{]+/, '')
  end
end

if __FILE__ == $0
  fb = FacebookChat.new(ARGV.shift, ARGV.shift)
  fb.login

  puts "Buddy List:"
  pp fb.buddy_list

  Thread.abort_on_exception = true
  Thread.new do
    puts usage = "Enter message as <facebook_id> <message> (eg: 124423 hey man wassup?) or type 'buddy' for buddy list"
    loop do
      case gets.strip
      when 'buddy' then pp fb.buddy_list
      when /^(\d+) (.+)$/
        uid, text = $1.to_i, $2
        fb.send_message(uid, text)
      else
        puts usage
      end
    end
  end

  # message receiving loop
  loop do
    fb.wait_for_messages.each do |msg|
      puts "[#{msg.time.strftime('%H:%M')}] #{msg.from_name} (#{msg.from}): #{msg.text}"
    end
  end
end