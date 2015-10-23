require 'securerandom'
require 'digest'
require 'base64'

class Utils
  def filehash_maker(ident,filename,conid)
    content = File.read(filename)
    (Digest::SHA256.new << conid + "-#{ident}-" + content).base64digest
  end

  def packet_mangler(sash,header)
    header +"\n"+ sash.map{|k,v| "#{k}=#{v}"}.join("\n") + "\nEndMessage\n"
  end
  
  def id_generate
    SecureRandom.hex
  end
end
