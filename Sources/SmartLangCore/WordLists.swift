import Foundation

/// Small built-in word lists. The app adds the macOS spell checker for
/// English, so this list mostly matters for tests and short common words.
/// Thai has no system spell checker, so the Thai list is larger; add your own
/// words in Settings → Custom Thai words.
public enum WordLists {
    public static let english: Set<String> = Set(englishRaw.split(whereSeparator: \.isWhitespace).map(String.init))
    public static let thai: Set<String> = Set(thaiRaw.split(whereSeparator: \.isWhitespace).map(String.init))

    static let englishRaw = """
    the be to of and a in that have i it for not on with he as you do at this but his by from they we say her
    she or an will my one all would there their what so up out if about who get which go me when make can like
    time no just him know take people into year your good some could them see other than then now look only come
    its over think also back after use two how our work first well way even new want because any these give day
    most us is are was were been has had did does done said made went gone got seen knew took came thought
    told found gave used called asked felt left kept let put meant set run ran
    hello hi hey yes yeah ok okay thanks thank please sorry welcome bye goodbye morning night evening afternoon
    today tomorrow yesterday week month weekend monday tuesday wednesday thursday friday saturday sunday
    january february march april may june july august september october november december
    man woman child children boy girl friend family mother father mom dad brother sister baby son daughter
    wife husband home house room door window table chair bed car bus train plane road street city country
    world school student teacher class lesson book paper pen phone computer laptop email message text chat
    meeting office job company business team project plan idea problem question answer reason result
    money price cost pay buy sell shop store market food water coffee tea rice milk bread meat fish chicken
    egg fruit apple banana lunch dinner breakfast eat drink cook kitchen restaurant hotel trip travel
    life love hate happy sad angry tired sick health doctor hospital medicine body head hand eye face heart
    big small large little long short high low old young early late fast slow hot cold warm cool easy hard
    right wrong true false best better worse worst great nice bad fine sure real free full open close
    important different same next last few many much more less own every each both such very really
    always never often sometimes usually again still already almost enough only quite rather maybe
    here where why while until since though although before during under between through without within
    against around above below near far off down again away together
    need feel try leave call keep start show hear play move live believe hold bring happen write sit stand
    lose meet include continue learn change lead understand watch follow stop create speak read spend grow
    win offer remember consider appear wait serve die send expect build stay fall cut reach kill remain
    suggest raise pass report decide pull open close help talk turn ask tell find walk add check fix test
    love miss agree hope wish care thank sleep wake drive fly swim sing dance draw cook clean wash wear
    something nothing anything everything someone anyone everyone nobody somewhere anywhere everywhere
    thing things person place part case point group number fact hand eye side kind head fact
    word words name line end order area lot form story level system program water service music game
    movie video photo picture film news point issue side party health art war history power
    hour minute second moment year years days weeks months times
    please could should would might must shall can't don't won't isn't aren't wasn't weren't didn't
    doesn't haven't hasn't couldn't shouldn't wouldn't i'm you're we're they're it's that's what's
    let's i've i'll i'd you'll you've he's she's there's
    one two three four five six seven eight nine ten hundred thousand million first second third
    red blue green yellow black white pink purple orange brown gray grey color colour
    thai english language keyboard input type typing layout mac apple app software code file folder
    google github slack line facebook youtube website internet online link password account login user
    data list key test update version error bug issue fix build release
    able about above across act action actually add address age ago air allow alone along among another
    answer area arm art article attack author available away base beautiful become bed behind
    believe beyond bill black blood board born box break brother budget camera cancer candidate
    capital card career carry catch cause cell center central century certain chance character charge
    choice choose church citizen claim clear coach collection college come commercial common community
    compare computer concern condition conference control court cover cultural culture cup current
    customer dark deal death debate decade deep defense degree democratic describe design detail
    develop development difference difficult dinner direction director discover discuss disease
    economy edge education effect effort either election else employee energy enjoy entire
    environment especially establish evening event evidence exactly example executive exist
    experience expert explain fail fear federal feeling field fight figure fill final finally
    financial finger fire firm floor focus foot force foreign forget former forward future garden
    gas general generation glass goal government ground growth guess gun hair half hang heat heavy
    hit hope huge human husband image imagine impact improve increase indeed indicate individual
    industry information inside instead institution interest interesting international interview
    investment involve item itself join just keep kid kill knowledge land language laugh law lawyer
    lay leader least legal letter lie light likely listen local machine magazine main maintain
    major majority manage management manager material matter mean measure media member memory
    mention method middle military mind mission model modern mouth movement nation national natural
    nature necessary network never nice north note notice number occur official oil operation
    opportunity option organization others outside owner page pain painting paper parent particular
    partner past patient pattern peace perform performance perhaps period physical piece player
    police policy political politics poor popular population position positive possible practice
    prepare present president pressure pretty prevent private probably process produce product
    production professional professor property protect prove provide public purpose quality quickly
    quiet race radio range rate reality realize receive recent recently recognize record reduce
    reflect region relate relationship religious represent require research resource respond
    response responsibility rest return reveal rich rise risk rock role rule safe scene science
    scientist score sea season seat security seek seem sense series serious set seven several sex
    shake share shoot short shot shoulder sign significant similar simple simply single sir site
    situation skill skin smile social society soldier somebody song soon sort sound source south
    southern space speech sport spring staff stage standard star state statement station step stock
    stuff style subject success successful suddenly suffer summer support surface table task tax
    technology television tell tend term terms than thank themselves theory these thing third
    those threat throughout throw thus total tough toward town trade traditional treat treatment
    tree trial trouble truth tv two type unit up upon usually value various victim view violence
    visit voice vote wall weapon wear weight west western whatever whether white whole whom whose
    wide wind wish woman wonder worker writer yard yet
    """

    static let thaiRaw = """
    สวัสดี ครับ ค่ะ คะ ขอบคุณ ขอโทษ ไม่ ใช่ ได้ เป็น อยู่ คือ มี ไป มา ทำ ให้ และ หรือ แต่ ก็ ที่ ของ ใน กับ จาก
    ถึง แล้ว จะ กำลัง เคย ยัง อีก นี้ นั้น โน้น นี่ นั่น โน่น อะไร ใคร ที่ไหน เมื่อไร เมื่อไหร่ ทำไม อย่างไร ยังไง
    เท่าไร เท่าไหร่ กี่ ไหม มั้ย หรือเปล่า เปล่า ล่ะ นะ จ้ะ จ้า จ๊ะ ฮะ เถอะ สิ ซิ น่ะ หรอก เลย ด้วย
    ผม ฉัน ดิฉัน เรา เขา เธอ คุณ มัน ท่าน พวก กู มึง หนู พี่ น้อง พ่อ แม่ ลูก ปู่ ย่า ตา ยาย ลุง ป้า น้า อา
    เพื่อน แฟน สามี ภรรยา ครู นักเรียน นักศึกษา หมอ คน ผู้ชาย ผู้หญิง เด็ก ผู้ใหญ่ ครอบครัว
    กิน ดื่ม นอน ตื่น อาบน้ำ เดิน วิ่ง นั่ง ยืน พูด คุย บอก ถาม ตอบ ฟัง ดู เห็น อ่าน เขียน เรียน สอน รู้ เข้าใจ
    คิด จำ ลืม ชอบ รัก เกลียด อยาก ต้องการ ต้อง ควร อาจ คง น่าจะ ช่วย ใช้ ซื้อ ขาย จ่าย เปิด ปิด ส่ง รับ
    เอา วาง ถือ หา เจอ พบ เล่น ทำงาน ขับ ขี่ นั่ง รอ เริ่ม เสร็จ จบ หยุด กลับ ออก เข้า ขึ้น ลง ข้าม ตาม
    เรียก โทร ตั้ง แก้ แปล เปลี่ยน สลับ พิมพ์ ลอง ทดสอบ เลือก ชนะ แพ้ เกิด ตาย อยู่ ย้าย พัก ฝัน หัวเราะ ร้องไห้
    ดี เลว สวย หล่อ น่ารัก ใหญ่ เล็ก ยาว สั้น สูง ต่ำ เตี้ย อ้วน ผอม ร้อน หนาว เย็น อุ่น เร็ว ช้า ง่าย ยาก
    ใหม่ เก่า แพง ถูก ผิด จริง มาก น้อย หลาย ทุก บาง ทั้ง เยอะ นิด หน่อย นิดหน่อย สนุก เบื่อ เหนื่อย หิว อิ่ม
    ง่วง ป่วย สบาย สบายดี ดีใจ เสียใจ โกรธ กลัว ห่วง สำคัญ พร้อม ว่าง ยุ่ง เต็ม หมด สะอาด สกปรก
    วัน คืน เช้า สาย บ่าย เย็น ค่ำ ดึก วันนี้ พรุ่งนี้ เมื่อวาน ตอนนี้ เดี๋ยวนี้ เดี๋ยว ทีหลัง ก่อน หลัง ระหว่าง
    เวลา ชั่วโมง นาที วินาที สัปดาห์ อาทิตย์ เดือน ปี ครั้ง ตอน ช่วง
    จันทร์ อังคาร พุธ พฤหัส พฤหัสบดี ศุกร์ เสาร์ มกราคม กุมภาพันธ์ มีนาคม เมษายน พฤษภาคม มิถุนายน
    กรกฎาคม สิงหาคม กันยายน ตุลาคม พฤศจิกายน ธันวาคม
    หนึ่ง สอง สาม สี่ ห้า หก เจ็ด แปด เก้า สิบ ยี่สิบ ร้อย พัน หมื่น แสน ล้าน
    บ้าน ห้อง ประตู หน้าต่าง โต๊ะ เก้าอี้ เตียง รถ รถไฟ เครื่องบิน เรือ ถนน ทาง เมือง ประเทศ โลก
    โรงเรียน มหาวิทยาลัย บริษัท ออฟฟิศ ที่ทำงาน ร้าน ตลาด โรงแรม โรงพยาบาล วัด ทะเล ภูเขา แม่น้ำ
    อาหาร ข้าว น้ำ กาแฟ ชา นม ขนม ผลไม้ ผัก เนื้อ หมู ไก่ ปลา กุ้ง ไข่ ก๋วยเตี๋ยว ส้มตำ ต้มยำ ผัดไทย
    อร่อย เผ็ด หวาน เค็ม เปรี้ยว ขม
    เงิน ราคา บาท งาน เรื่อง ปัญหา คำถาม คำตอบ ความ การ ภาษา ไทย อังกฤษ คำ ประโยค หนังสือ กระดาษ
    โทรศัพท์ มือถือ คอมพิวเตอร์ แป้นพิมพ์ คีย์บอร์ด อินเทอร์เน็ต ข้อความ อีเมล ไฟล์ แอป โปรแกรม
    เพลง หนัง รูป ภาพ ข่าว เกม กีฬา ฟุตบอล
    หัว ตา หู จมูก ปาก มือ เท้า ขา แขน ตัว ใจ หัวใจ ร่างกาย
    สี แดง เขียว น้ำเงิน ฟ้า เหลือง ขาว ดำ ชมพู ม่วง ส้ม
    ทำไม เพราะ เพราะว่า ถ้า หาก ว่า เมื่อ จน จนถึง เพื่อ โดย แบบ อย่าง เหมือน กว่า ที่สุด เท่านั้น เท่า
    นอก ใต้ บน ข้าง หน้า ข้างหน้า ข้างหลัง ซ้าย ขวา ใกล้ ไกล ตรง ตรงนี้ ที่นี่ ที่นั่น
    เลข ตัวเลข แรก สุดท้าย ต่อ ไป ต่อไป อื่น อื่นๆ อีกครั้ง ด้วยกัน กัน เอง
    ประชุม โครงการ ระบบ ข้อมูล ทีม ลูกค้า แผน ผล ผลลัพธ์ ตัวอย่าง วิธี ความคิด ความรัก ความสุข
    สุข ทุกข์ สุขภาพ ชีวิต โชคดี ยินดี ต้อนรับ ยินดีต้อนรับ ไม่เป็นไร โอเค ค่อย ค่อยๆ
    """
}
