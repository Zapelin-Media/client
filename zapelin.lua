-- Copyright (C) 2019-2021 by Ubaldo Porcheddu <ubaldo@zapelin.com>


eja.lib.zmiStart='ejaZmiStart'
eja.lib.zmiStop='ejaZmiStop'
eja.lib.zmiInstall='ejaZmiInstall'
eja.lib.zmiUpdate='ejaZmiUpdate'
eja.lib.zmiConfigure='ejaZmiConfigure'
eja.help.zmiStart='launch a zmi instance {all}'
eja.help.zmiStop='stop a zmi instance {all}'
eja.help.zmiCard='zmi card number {0}'
eja.help.zmiCode='zmi card code'
eja.help.zmiUpdate='update the Zapelin Media Client'
eja.help.zmiInstall='install the Zapelin Media Client'
eja.help.zmiConfigure='zmi configuration'


eja.zmi={}
eja.zmi.timeout=86400;
eja.zmi.version="210917";


function ejaZmiUpdate()
 ejaExecute('eja --update')
 ejaExecute('eja --update http://get.zapelin.com/zapelin.eja')
end


function ejaZmiInstall()
 if not ejaFileStat('/usr/bin/apt') then
  ejaError('This installation does only work on Debian or a derivate.')
 else
  if not ejaDirList('/sys/kernel/debug') then
   ejaError('You need root/sudo privileges to execute this procedure.')
  else
   ejaExecute([[
apt update
apt install -y git
apt install -y ffmpeg
apt install -y build-essential
apt install -y linux-headers-$(uname -r)
mkdir /tmp/tv

cd /tmp/tv
git clone https://github.com/zapelin-media/ite.git
cd ite && ./install.sh
cd /tmp/tv
find /lib/modules -name "usb-it950x.ko" > /tmp/tv/ite.test
if [ ! -s /tmp/tv/ite.test ]; then
 git clone https://github.com/tsduck/hides-drivers.git
 cd hides-drivers/linux-drivers/it950x_driver
 make && make install
fi

cd /tmp/tv
git clone https://github.com/zapelin-media/dektec.git
cd dektec && ./install.sh
cd /tmp/tv
find /lib/modules -name "Dta.ko" > /tmp/tv/dektec.test
if [ ! -s /tmp/tv/dektec.test ]; then
 wget -O dektec.deb https://github.com/tsduck/dektec-dkms/releases/download/v2021.05.0/dektec-dkms_2021.05.0_all.deb && apt install -y ./dektec.deb 
fi

rm -Rf /tmp/tv

depmod 
modprobe usb-it950x
modprobe usb-it951x
modprobe Dta
]])
  end
  if not ejaFileStat('/etc/eja/eja.init') then
   ejaSetup()
   ejaFileWrite('/etc/eja/eja.init','eja.opt.zmiStart=1;eja.opt.logLevel=3;eja.opt.logFile="/tmp/eja.log";')
  else
   ejaFileAppend('/etc/eja/eja.init','eja.opt.zmiStart=1;')
  end
 ejaSleep(30)
 ejaZmiConfigure()
 end
end


function ejaZmiSerial(n)
 local mac=table.pack(ejaString(ejaGetMAC()):gsub('%:',''):upper():byte(1,12))
 local serial=''
 if ejaNumber(n) > 0 then
  local x=mac[n]
  if x >=65 and x<=70 then x=x+10 end
  if x >=48 and x<=57 then x=x+23 end
  mac[n]=x
 end
 for i=1,12 do serial=serial..string.char(mac[i]) end
 return serial
end 


function ejaZmiConfigure()
  local serial={}
  local i=0
  for k,v in next,ejaZmiCardMatrix() do
   serial[i]=ejaZmiSerial(i)
   ejaInfo('New card detected, model: %s, serial: %s',v,serial[i])
   i=i+1
  end
  if i == 0 then
   serial[0]=ejaZmiSerial(0)
   ejaInfo('No card detected, forcing rtp mode, serial: %s',serial[i])
  end
  ejaJsonFileWrite('/etc/eja/eja.dvb',serial)
  return serial
end


function ejaZmiStart()
 local mac=ejaZmiSerial(0);
 if eja.opt.zmiCode then
  ejaZmiRun(eja.opt.zmiCard, eja.opt.zmiCode)
 else
  local a=ejaJsonFileRead('/etc/eja/eja.dvb')
  if not a then
   a=ejaZmiConfigure()
  end
  if a then
   for k,v in next,a do
    if ejaNumber(k) == 0 then
     mac=ejaString(v)
    end
    if ejaFork()==0 then 
     ejaPidWrite(ejaSprintf('zmi.out.%s',k));
     ejaZmiRun(k,v)   
     os.exit(); 
    end
   end 
   ejaInfo('[zmi] log daemon start')
   while true do 
    ejaZmiLogUpdate(mac)
    ejaSleep(100)
   end
  end
 end
end


function ejaZmiStop(card)
 if card then
  ejaPidKill('zmi.out.'..card);
 else
  for k,v in next,ejaDirTable(eja.pathLock) do
   if v:match('^eja.pid.zmi.out') then
    ejaPidKill(v:match('^eja.pid.(.+)'))
   end
  end
 end
end


function ejaZmiCardMatrix() 
 local a={}
 local pciPath='/sys/bus/pci/devices'
 for k,v in next,ejaDirTable(pciPath) do
  if ejaString(ejaFileRead(pciPath..'/'..v..'/vendor')):lower():match('0x1a0e') and ejaString(ejaFileRead(pciPath..'/'..v..'/device')):lower():match('0x083f') then
   a[#a+1]='DTA-2111'
  end
 end
 for k,v in next,ejaDirList('/dev/') do
  if v:match('usb%-it950x.$') then 
   a[#a+1]='UT-100'
  end
  if v:match('usb%-it951x.$') then 
   a[#a+1]='UT-200'
  end
 end
 return a
end


function ejaZmiRun(card,hash)
 local card=card or eja.opt.zmiCard or 0
 local hash=hash or eja.opt.zmiCode
 local mode=0;
 if ejaString(hash) ~= '' then
  local cardMatrix=ejaZmiCardMatrix()
  if ejaString(cardMatrix[card+1]) == 'UT-100' then mode=10 end
  if ejaString(cardMatrix[card+1]) == 'UT-200' then mode=11 end
  if ejaString(cardMatrix[card+1]) == 'DTA-2111' then mode=20 end
  ejaInfo('[zmi] starting mux %s with code %s',card,hash)
  while true do
   local jj=ejaWebGet('http://api.zapelin.com/?zmi='..hash) 
   if jj then
    local a=ejaJsonDecode(jj)
    if a and a.vm then 
     loadstring(ejaVmImport(a.vm))()
    end
    if a and a.host and a.port then
     ejaDebug('[zmi] mux %d injecting',card)
     local cmdUrl=''
     local cmdOut=''
     if ejaString(a.proxy) ~= "" then
      cmdUrl=ejaSprintf('http://%s/proxy.zmx?host=%s&port=%s&hash=%s',a.proxy, a.host, a.port, hash)
     else
      cmdUrl=ejaSprintf('http://%s:%s/mux.zmx?hash=%s',a.host, a.port, hash)
     end
     if mode == 0 then
      if ejaString(a.rtpHost) ~= "" and ejaNumber(a.rtpPort) > 0 then
       cmdOut='';
       if ejaTableCount(a.channel) > 0 then
        local map={}
        i=0;
        for k,v in next, a.channel do
         map[#map+1]=ejaSprintf([[ -map 0:p:%d -program title="%s":program_num=%d:st=%d:st=%d ]], v.videoSid, v.videoLabel, v.videoSid, i, i+1);
         i=i+2;
        end                 
        cmdOut=ejaSprintf([[ffmpeg -nostats -nostdin -i - %s -c:v copy -c:a copy -muxrate %d -pcr_period 40 -f mpegts "udp://%s:%s?pkt_size=1316" 2>/dev/null]], table.concat(map), a.rate, a.rtpHost, a.rtpPort);
       else
        ejaWarning('[zmi] mux %d no channels available',card)
       end
      else
       ejaError('[zmi] mux %d no mode available',card)
       return false      
      end
     end
     if mode >= 10 and mode < 20 then
      cmdOut=ejaSprintf('zapelinItePlay %s %s %s %s %s %s %s %s 0 10', card, mode-10, ejaNumber(a.frequency)/1000, ejaNumber(a.bandwidth)/1000, a.constellation, a.codeRate, a.guardInterval, a.transmissionMode)
     end
     if mode >= 20 and mode < 30 then
      local aCodeRate={'1/2','2/3','3/4','5/6','7/8'}
      local aConstellation={'QPSK','QAM','QAM64'}
      local aTransmissionMode={'2k','8k','4k'}
      local aGuardInterval={'1/32','1/16','1/8','1/4'}
      cmdOut=ejaSprintf('zapelinDtPlay /proc/self/fd/0 -l 1 -r %s -t 2111 -n %s -m 188 -mt DVBT -mf %s -mc %s -mC %s -mB %s -mT %s -mG %s', 
       a.rate,ejaNumber(card)+1, ejaNumber(a.frequency)/1000, aCodeRate[ejaNumber(a.codeRate)+1], aConstellation[ejaNumber(a.constellation)+1], ejaNumber(a.bandwidth)/1000, 
       aTransmissionMode[ejaNumber(a.transmissionMode)+1], aGuardInterval[ejaNumber(a.guardInterval)+1]
      )
     end
     local cmd=ejaSprintf('(wget --timeout=100 -qO - "%s" | gzip -d | %s)', cmdUrl, cmdOut)
     ejaTrace('[zmi] cmd: %s', cmd)
     ejaExecute(cmd)
    else
     ejaWarn('[zmi] mux %d api configuration empty',card)
    end  
   else
    ejaError('[zmi] mux %d api retrieval problem',card)
   end
   ejaSleep(10)
  end
 else
  ejaError('[zmi] mux %d code missing',card)
 end
end


function ejaZmiLogUpdate(mac)
 local a={}
 local y=0
 local last=ejaFileRead(eja.pathLock..'eja.log.update') or 0
 for line in io.lines(eja.opt.logFile) do
  y=y+1
  if y > ejaNumber(last) then
   a[#a+1]=line
  end
 end
 if #a > 0 then
  ejaFileWrite(eja.pathLock..'eja.log.update',y)
  ejaTrace('[zmi] remote log update')
  return ejaJsonPost('http://api.zapelin.com/?log='..mac,a)
 else
  return {}
 end
end

