// Curated subset of the Mozilla Public Suffix List used by the autofill
// matcher to derive eTLD+1 (registrable domain) for subdomain matching.
//
// This is intentionally a small curated list rather than the full ~250KB
// PSL — it covers the multi-part TLDs that most users will hit
// (`co.uk`, `com.au`, `co.jp`, …) without bloating the binary or
// requiring runtime asset loading. Single-part TLDs (`.com`, `.org`,
// `.net`, …) fall through the default "last two labels" rule.
//
// Mirrored by `autofill/matcher/PublicSuffixList.kt` on the Kotlin side
// — keep the two sets in sync.

class PublicSuffixList {
  PublicSuffixList._();

  static const Set<String> _multiPartSuffixes = {
    'co.uk', 'ac.uk', 'gov.uk', 'org.uk', 'net.uk', 'sch.uk', 'me.uk',
    'plc.uk', 'ltd.uk', 'nhs.uk', 'police.uk',
    'co.jp', 'ac.jp', 'ne.jp', 'or.jp', 'go.jp', 'gr.jp', 'lg.jp',
    'co.kr', 'ne.kr', 'or.kr', 'pe.kr', 'go.kr', 'ac.kr',
    'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au', 'asn.au', 'id.au',
    'com.br', 'net.br', 'org.br', 'gov.br', 'edu.br', 'mil.br',
    'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'ac.cn',
    'co.in', 'net.in', 'org.in', 'gov.in', 'edu.in', 'ac.in',
    'co.za', 'net.za', 'org.za', 'gov.za', 'edu.za',
    'co.nz', 'net.nz', 'org.nz', 'gov.nz', 'school.nz',
    'com.mx', 'net.mx', 'org.mx', 'gob.mx', 'edu.mx',
    'com.ar', 'net.ar', 'org.ar', 'gov.ar', 'edu.ar',
    'com.tr', 'net.tr', 'org.tr', 'gov.tr', 'edu.tr',
    'com.tw', 'net.tw', 'org.tw', 'gov.tw', 'edu.tw',
    'com.sg', 'net.sg', 'org.sg', 'gov.sg', 'edu.sg', 'per.sg',
    'com.hk', 'net.hk', 'org.hk', 'gov.hk', 'edu.hk', 'idv.hk',
    'co.il', 'net.il', 'org.il', 'gov.il', 'ac.il', 'k12.il',
    'co.id', 'net.id', 'org.id', 'go.id', 'sch.id', 'web.id',
    'com.eg', 'net.eg', 'org.eg', 'gov.eg', 'edu.eg',
    'com.sa', 'net.sa', 'org.sa', 'gov.sa', 'edu.sa', 'med.sa',
    'com.my', 'net.my', 'org.my', 'gov.my', 'edu.my',
    'com.ph', 'net.ph', 'org.ph', 'gov.ph', 'edu.ph',
    'com.vn', 'net.vn', 'org.vn', 'gov.vn', 'edu.vn',
    'com.pe', 'net.pe', 'org.pe', 'gob.pe', 'edu.pe',
    'com.co', 'net.co', 'org.co', 'gov.co', 'edu.co',
    'com.ve', 'net.ve', 'org.ve', 'gov.ve', 'edu.ve',
    'com.uy', 'net.uy', 'org.uy', 'gub.uy', 'edu.uy',
    'co.th', 'net.th', 'or.th', 'go.th', 'ac.th', 'in.th',
    'com.pk', 'net.pk', 'org.pk', 'gov.pk', 'edu.pk',
    'com.bd', 'net.bd', 'org.bd', 'gov.bd', 'edu.bd',
    'com.ng', 'net.ng', 'org.ng', 'gov.ng', 'edu.ng',
    'com.kw', 'net.kw', 'org.kw', 'gov.kw', 'edu.kw',
    'com.qa', 'net.qa', 'org.qa', 'gov.qa', 'edu.qa',
    'com.bh', 'net.bh', 'org.bh', 'gov.bh', 'edu.bh',
    'com.ec', 'net.ec', 'org.ec', 'gob.ec', 'edu.ec',
    'com.gt', 'net.gt', 'org.gt', 'gob.gt', 'edu.gt',
    'com.do', 'net.do', 'org.do', 'gob.do', 'edu.do',
    'com.bo', 'net.bo', 'org.bo', 'gob.bo', 'edu.bo',
    'com.cy', 'net.cy', 'org.cy', 'gov.cy', 'edu.cy',
    'co.ke', 'ne.ke', 'or.ke', 'go.ke', 'ac.ke',
    'com.gh', 'net.gh', 'org.gh', 'gov.gh', 'edu.gh',
    'com.lb', 'net.lb', 'org.lb', 'gov.lb', 'edu.lb',
    'co.cr', 'ac.cr', 'go.cr', 'or.cr', 'ed.cr', 'fi.cr',
  };

  /// Returns the eTLD+1 (registrable domain) for [host], e.g.
  /// `login.example.co.uk` → `example.co.uk`. Falls back to the original
  /// host if the input has fewer than two labels.
  static String etldPlus1(String host) {
    final parts = host.split('.');
    if (parts.length < 2) return host;

    if (parts.length >= 3) {
      final twoLevel = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
      if (_multiPartSuffixes.contains(twoLevel)) {
        return '${parts[parts.length - 3]}.$twoLevel';
      }
    }

    return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  }

  /// True when [host] is the same registrable domain as [registrable] or
  /// a subdomain of it. `login.example.co.uk` matches `example.co.uk`.
  static bool isSameOrSubdomain(String host, String registrable) {
    if (host == registrable) return true;
    return host.endsWith('.$registrable');
  }
}
