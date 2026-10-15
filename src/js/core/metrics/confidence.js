export function confidenceFor({value,missing=[],exclusions=[],source_count=0}) {
 if(value==null)return 'UNAVAILABLE';
 if(missing.length||exclusions.length)return 'LOW';
 // Imported records do not certify completeness of the company's books.
 return source_count?'MEDIUM':'LOW';
}
