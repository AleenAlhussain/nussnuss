/**
 * Privacy policy and terms, in English and Arabic. Plain language, matched to what the code does.
 * Keep this in step with the App Store privacy label and the Google Play data safety form.
 */
export interface LegalDoc {
  title: string;
  updated: string;
  intro: string;
  sections: { h: string; p: string[] }[];
}

const UPDATED = '2026-10-26';

export const privacy: Record<'en' | 'ar', LegalDoc> = {
  en: {
    title: 'Privacy',
    updated: `Last updated ${UPDATED}`,
    intro: 'NussNuss keeps only what it needs to split bills with your friends. There are no ads and no advertising or tracking tools in the app or on the website.',
    sections: [
      {
        h: 'What we keep',
        p: [
          'The name you choose, your language, and the groups you make or join: their names, the people in them, the expenses (title, amount, currency, who paid, how it was split, the date) and payments marked as paid.',
          'If you choose one: a profile photo (kept small, 256 × 256), or an emoji, and a colour. Friends in your groups see it next to your name.',
          'If you add them: ways friends can pay you (such as an IBAN or a payment link), a passkey, or a link to your Apple or Google sign-in. From Apple or Google we keep the account identifier and, if they share it, your email address.',
          'A recovery code is stored only as a scrambled fingerprint (a hash), so nobody can read it back.',
          'For each signed-in device: a short device name (for example “Safari on iPhone”) and when it was last used.',
        ],
      },
      {
        h: 'Who sees it',
        p: [
          'Everyone in a group sees that group: its people, expenses, payments and the ways each person has chosen to be paid. Anyone with an invite link can see a group’s name and the names in it until the link expires after 30 days.',
          'We do not sell or share your information with anyone else. Purchases are handled by the App Store or Google Play; we receive a transaction record to switch on what you bought, never your card.',
        ],
      },
      {
        h: 'Optional services',
        p: [
          'Reminders: if a group turns on weekly reminders, the app sends a notification to people who owe money. Push notifications use Apple’s and Google’s notification services, which receive a device token.',
          'Live exchange rates are looked up by currency only; nothing about you is sent.',
          'Crash reports, when the server operator turns them on, contain only the error message and where in the code it happened. Long secrets and email addresses are removed before they are stored.',
          'Task timings, when the server operator turns them on: how long adding an expense, splitting unevenly, settling up, inviting or finding your balance took, and whether it finished. They carry the app and its version, and nothing about you, your device or your groups.',
        ],
      },
      {
        h: 'Your choices',
        p: [
          'Download my data (Settings) gives you everything we hold about you as one file.',
          'Delete my account (Settings) removes your account from every device. In shared groups your name becomes “Former member” so your friends’ balances still add up.',
          'You can remove payment details, passkeys and signed-in devices at any time in Settings.',
        ],
      },
      {
        h: 'Keeping it safe',
        p: [
          'Everything travels over HTTPS. Sign-in tokens are stored hashed on the server and, in the phone app, in the iPhone Keychain or Android Keystore. Databases are backed up daily and old backups are deleted after 14 days.',
          'NussNuss is not meant for children under 13.',
        ],
      },
      {
        h: 'Questions',
        p: ['Write to the support address on the NussNuss page in the App Store or Google Play. If this policy changes, the date at the top changes and the app tells you about important changes.'],
      },
    ],
  },
  ar: {
    title: 'الخصوصية',
    updated: `آخر تحديث ${UPDATED}`,
    intro: 'نص نص يحتفظ فقط بما يلزم لتقسيم الفواتير مع أصحابك. لا إعلانات، ولا أدوات إعلان أو تتبّع في التطبيق أو الموقع.',
    sections: [
      {
        h: 'ما نحتفظ به',
        p: [
          'الاسم الذي تختاره، ولغتك، والمجموعات التي تنشئها أو تنضم إليها: أسماؤها، والأشخاص فيها، والمصاريف (الوصف، المبلغ، العملة، مين دفع، طريقة التقسيم، التاريخ) والدفعات المسجّلة.',
          'إذا اخترت: صورة شخصية (صغيرة، ٢٥٦ × ٢٥٦) أو إيموجي، ولونًا. يراها أصحابك في مجموعاتك بجانب اسمك.',
          'إذا أضفتها: طرق استلامك للفلوس (مثل IBAN أو رابط دفع)، أو مفتاح مرور، أو ربط حسابك في Apple أو Google. من Apple أو Google نحتفظ بمعرّف الحساب، وبريدك الإلكتروني إن شاركوه.',
          'رمز الاستعادة يُحفظ كبصمة مشفّرة فقط (hash)، فلا يمكن لأحد قراءته.',
          'لكل جهاز مسجّل: اسم مختصر للجهاز (مثل "Safari على iPhone") ووقت آخر استخدام.',
        ],
      },
      {
        h: 'مين يشوفها',
        p: [
          'كل أعضاء المجموعة يشوفون المجموعة: أشخاصها، ومصاريفها، ودفعاتها، وطرق الاستلام التي اختارها كل شخص. ومن عنده رابط الدعوة يشوف اسم المجموعة والأسماء فيها حتى ينتهي الرابط بعد ٣٠ يومًا.',
          'لا نبيع معلوماتك ولا نشاركها مع أي جهة أخرى. المشتريات يتولاها App Store أو Google Play؛ نستلم سجل العملية لتفعيل ما اشتريته، ولا نرى بطاقتك أبدًا.',
        ],
      },
      {
        h: 'خدمات اختيارية',
        p: [
          'التذكير: إذا فعّلت المجموعة التذكير الأسبوعي، يرسل التطبيق إشعارًا لمن عليهم فلوس. الإشعارات تمر عبر خدمات Apple وGoogle، وتستلم رمزًا خاصًا بالجهاز.',
          'أسعار الصرف المباشرة تُطلب بالعملة فقط؛ لا يُرسل شيء عنك.',
          'تقارير الأعطال، إذا فعّلها مشغّل الخادم، تحتوي فقط على رسالة الخطأ ومكانه في الكود. تُحذف الرموز الطويلة والبريد الإلكتروني قبل الحفظ.',
          'أوقات المهام، إذا فعّلها مشغّل الخادم: كم استغرقت إضافة مصروف، أو التقسيم غير المتساوي، أو التسوية، أو الدعوة، أو معرفة رصيدك، وهل اكتملت. تحمل اسم التطبيق وإصداره فقط، ولا شيء عنك أو عن جهازك أو مجموعاتك.',
        ],
      },
      {
        h: 'اختياراتك',
        p: [
          '"نزّل بياناتي" في الإعدادات يعطيك كل ما نحتفظ به عنك في ملف واحد.',
          '"احذف حسابي" في الإعدادات يحذف حسابك من كل الأجهزة. في المجموعات المشتركة يصبح اسمك "عضو سابق" حتى تبقى حسابات أصحابك صحيحة.',
          'تقدر تحذف طرق الاستلام ومفاتيح المرور والأجهزة المسجّلة بأي وقت من الإعدادات.',
        ],
      },
      {
        h: 'الحماية',
        p: [
          'كل شيء ينتقل عبر HTTPS. رموز الدخول محفوظة مشفّرة على الخادم، وفي تطبيق الجوال داخل Keychain في iPhone أو Keystore في Android. قواعد البيانات تُنسخ احتياطيًا يوميًا وتُحذف النسخ القديمة بعد ١٤ يومًا.',
          'نص نص غير مخصص للأطفال تحت ١٣ سنة.',
        ],
      },
      {
        h: 'أسئلة',
        p: ['راسل عنوان الدعم الموجود في صفحة نص نص على App Store أو Google Play. إذا تغيّرت هذه السياسة يتغيّر التاريخ في الأعلى، ويخبرك التطبيق بالتغييرات المهمة.'],
      },
    ],
  },
};

export const terms: Record<'en' | 'ar', LegalDoc> = {
  en: {
    title: 'Terms',
    updated: `Last updated ${UPDATED}`,
    intro: 'These terms cover using NussNuss in the app and on the web. By using it you agree to them.',
    sections: [
      {
        h: 'What NussNuss does',
        p: [
          'NussNuss helps you record shared costs and work out who owes whom. It does not hold, send or receive money. “Pay with” buttons open a payment service you already use, or copy the details your friend shared; any payment happens there, under that service’s terms.',
          'Money circles are for keeping track only: who pays each round and whose turn it is. The money moves between the people in the circle, not through NussNuss.',
        ],
      },
      {
        h: 'Free, and Plus',
        p: [
          'Splitting is free with no limits: groups, people, expenses, every split and currency, settling up and invite links.',
          'NussNuss Plus, the Trip Pass and Looks are optional purchases made through the App Store or Google Play. Subscriptions renew until you cancel them in your store account settings; the store handles billing and refunds under its own rules. A Trip Pass opens Plus features for everyone in one group for 30 days. Looks you buy stay yours.',
        ],
      },
      {
        h: 'Your part',
        p: [
          'Add only people who are happy to be in the group, and keep amounts honest. Do not use NussNuss to harass anyone, to break the law, or to try to get into other people’s accounts.',
          'Keep your recovery code private. Anyone who has it can sign in as you.',
        ],
      },
      {
        h: 'Our part',
        p: [
          'We work to keep NussNuss available and your data safe, and we check the arithmetic carefully, but the app is provided as it is. Check important amounts before you pay. To the extent the law allows, we are not responsible for losses that come from relying on the app.',
          'We may change the app or these terms. Important changes will be shown in the app before they apply. You can stop using NussNuss and delete your account at any time.',
        ],
      },
    ],
  },
  ar: {
    title: 'الشروط',
    updated: `آخر تحديث ${UPDATED}`,
    intro: 'هذه الشروط تخص استخدام نص نص في التطبيق والموقع. باستخدامه أنت توافق عليها.',
    sections: [
      {
        h: 'وش يسوي نص نص',
        p: [
          'نص نص يساعدك تسجّل المصاريف المشتركة وتعرف مين عليه لمين. لا يحتفظ بالفلوس ولا يرسلها ولا يستلمها. أزرار "ادفع عبر" تفتح خدمة دفع تستخدمها أصلًا، أو تنسخ التفاصيل التي شاركها صاحبك؛ والدفع يتم هناك وفق شروط تلك الخدمة.',
          'الجمعيات للمتابعة فقط: مين دفع في كل دور ودور مين. الفلوس تنتقل بين أعضاء الجمعية مباشرة، مو عن طريق نص نص.',
        ],
      },
      {
        h: 'مجاني، وبلس',
        p: [
          'التقسيم مجاني وبلا حدود: المجموعات، والأشخاص، والمصاريف، وكل طرق التقسيم والعملات، والتسوية، وروابط الدعوة.',
          'نص نص بلس وتذكرة الرحلة والإطلالات مشتريات اختيارية عبر App Store أو Google Play. الاشتراكات تتجدد حتى تلغيها من إعدادات حسابك في المتجر؛ والمتجر يتولى الدفع والاسترداد وفق قواعده. تذكرة الرحلة تفتح مزايا بلس لكل أعضاء مجموعة واحدة لمدة ٣٠ يومًا. والإطلالات التي تشتريها تبقى لك.',
        ],
      },
      {
        h: 'دورك',
        p: [
          'أضف فقط الأشخاص الراضين بوجودهم في المجموعة، وسجّل المبالغ بأمانة. لا تستخدم نص نص لمضايقة أحد، أو لمخالفة القانون، أو لمحاولة دخول حسابات الآخرين.',
          'احتفظ برمز الاستعادة لنفسك. من يملكه يقدر يدخل باسمك.',
        ],
      },
      {
        h: 'دورنا',
        p: [
          'نعمل على أن يبقى نص نص متاحًا وبياناتك آمنة، ونراجع الحسابات بعناية، لكن التطبيق مقدَّم كما هو. راجع المبالغ المهمة قبل الدفع. وبالقدر الذي يسمح به القانون، لسنا مسؤولين عن خسائر ناتجة عن الاعتماد على التطبيق.',
          'قد نغيّر التطبيق أو هذه الشروط، وسنعرض التغييرات المهمة في التطبيق قبل تطبيقها. تقدر تتوقف عن استخدام نص نص وتحذف حسابك بأي وقت.',
        ],
      },
    ],
  },
};
