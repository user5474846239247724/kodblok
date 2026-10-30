import Foundation

// MARK: - Opisi funkcija, ključnih reči i biblioteka (za listu dopunjavanja i oblačiće)

enum DocKind: String {
    case function, keyword, type, object, member, macro, variable, userFunction, directive, header, field

    var badge: String {
        switch self {
        case .function, .userFunction: return "f"
        case .keyword: return "k"
        case .type: return "T"
        case .object: return "o"
        case .member, .field: return "m"
        case .macro, .directive: return "#"
        case .variable: return "v"
        case .header: return "h"
        }
    }
}

enum DocLang { case c, cpp }

struct DocItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let signature: String
    let header: String
    let summary: String
    let kind: DocKind
    let lang: DocLang

    static func == (a: DocItem, b: DocItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var isCallable: Bool {
        (kind == .function || kind == .userFunction || kind == .member) && signature.contains("(")
    }

    var hasParams: Bool {
        guard let open = signature.firstIndex(of: "("), let close = signature.lastIndex(of: ")"), open < close else { return false }
        let inside = signature[signature.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return !(inside.isEmpty || inside == "void")
    }
}

enum CodeDocs {
    private static func f(_ n: String, _ sig: String, _ h: String, _ s: String, _ l: DocLang = .c) -> DocItem {
        DocItem(name: n, signature: sig, header: h, summary: s, kind: .function, lang: l)
    }
    private static func k(_ n: String, _ s: String, _ l: DocLang = .c, kind: DocKind = .keyword) -> DocItem {
        DocItem(name: n, signature: n, header: kind == .type ? "tip podatka" : "ključna reč", summary: s, kind: kind, lang: l)
    }
    private static func o(_ n: String, _ sig: String, _ h: String, _ s: String, _ kind: DocKind = .object, _ l: DocLang = .cpp) -> DocItem {
        DocItem(name: n, signature: sig, header: h, summary: s, kind: kind, lang: l)
    }
    private static func m(_ n: String, _ sig: String, _ owner: String, _ s: String) -> DocItem {
        DocItem(name: n, signature: sig, header: owner, summary: s, kind: .member, lang: .cpp)
    }

    // MARK: Funkcije i objekti iz biblioteka
    static let library: [DocItem] = [
        // <stdio.h>
        f("printf", "int printf(const char *format, ...)", "<stdio.h>",
          "Ispisuje formatiran tekst na ekran. Formati: %d ceo broj, %f realan broj, %.2f dve decimale, %c znak, %s string, %x heksadecimalno, %% znak %. \\n prelazi u novi red. Primer: printf(\"x = %d\\n\", x);"),
        f("scanf", "int scanf(const char *format, ...)", "<stdio.h>",
          "Učitava vrednosti sa tastature po formatu (%d, %f, %lf za double, %c, %s). Ispred promenljivih ide & (adresa), osim za stringove. Vraća broj uspešno učitanih vrednosti. Primer: scanf(\"%d\", &x);"),
        f("puts", "int puts(const char *s)", "<stdio.h>", "Ispisuje string i automatski prelazi u novi red."),
        f("putchar", "int putchar(int c)", "<stdio.h>", "Ispisuje jedan znak. Primer: putchar('A');"),
        f("getchar", "int getchar(void)", "<stdio.h>", "Učitava jedan znak sa tastature i vraća ga (ili EOF na kraju unosa)."),
        f("fgets", "char *fgets(char *s, int n, FILE *stream)", "<stdio.h>",
          "Učitava celu liniju (najviše n-1 znakova) u niz s, zajedno sa '\\n'. Bezbedna zamena za gets. Primer: fgets(ime, 50, stdin);"),
        f("gets", "char *gets(char *s)", "<stdio.h>", "ZASTARELO i opasno (nema ograničenje dužine) — koristi fgets(s, n, stdin)."),
        f("fopen", "FILE *fopen(const char *ime, const char *mod)", "<stdio.h>",
          "Otvara fajl. Mod: \"r\" čitanje, \"w\" pisanje (briše stari sadržaj), \"a\" dopisivanje, \"rb\"/\"wb\" binarno. Vraća NULL ako ne uspe — uvek proveri!"),
        f("fclose", "int fclose(FILE *fp)", "<stdio.h>", "Zatvara fajl otvoren sa fopen. Uvek zatvori fajl kad završiš."),
        f("fprintf", "int fprintf(FILE *fp, const char *format, ...)", "<stdio.h>", "Kao printf, ali piše u fajl. Primer: fprintf(f, \"%d\\n\", x);"),
        f("fscanf", "int fscanf(FILE *fp, const char *format, ...)", "<stdio.h>", "Kao scanf, ali čita iz fajla. Vraća EOF kad dođe do kraja fajla."),
        f("fgetc", "int fgetc(FILE *fp)", "<stdio.h>", "Čita jedan znak iz fajla (EOF na kraju)."),
        f("fputc", "int fputc(int c, FILE *fp)", "<stdio.h>", "Upisuje jedan znak u fajl."),
        f("fputs", "int fputs(const char *s, FILE *fp)", "<stdio.h>", "Upisuje string u fajl (bez automatskog novog reda)."),
        f("feof", "int feof(FILE *fp)", "<stdio.h>", "Vraća različito od 0 kada je dostignut kraj fajla."),
        f("fread", "size_t fread(void *ptr, size_t vel, size_t n, FILE *fp)", "<stdio.h>", "Čita n elemenata veličine vel iz binarnog fajla u memoriju ptr."),
        f("fwrite", "size_t fwrite(const void *ptr, size_t vel, size_t n, FILE *fp)", "<stdio.h>", "Upisuje n elemenata veličine vel u binarni fajl."),
        f("sprintf", "int sprintf(char *s, const char *format, ...)", "<stdio.h>", "Kao printf, ali rezultat upisuje u string s umesto na ekran."),
        f("sscanf", "int sscanf(const char *s, const char *format, ...)", "<stdio.h>", "Kao scanf, ali čita iz stringa s."),
        // <stdlib.h>
        f("malloc", "void *malloc(size_t velicina)", "<stdlib.h>",
          "Rezerviše (alocira) memoriju od zadatog broja bajtova i vraća pokazivač na nju (NULL ako nema memorije). Primer: int *a = malloc(n * sizeof(int)); Ne zaboravi free(a)."),
        f("calloc", "void *calloc(size_t n, size_t velicina)", "<stdlib.h>", "Alocira memoriju za n elemenata i postavlja je na nule."),
        f("realloc", "void *realloc(void *ptr, size_t nova_velicina)", "<stdlib.h>", "Menja veličinu prethodno alocirane memorije (može da je premesti)."),
        f("free", "void free(void *ptr)", "<stdlib.h>", "Oslobađa memoriju dobijenu sa malloc/calloc/realloc."),
        f("exit", "void exit(int status)", "<stdlib.h>", "Odmah prekida program. exit(0) znači uspešan kraj."),
        f("abs", "int abs(int x)", "<stdlib.h>", "Apsolutna vrednost celog broja. Za realne brojeve koristi fabs."),
        f("rand", "int rand(void)", "<stdlib.h>", "Vraća pseudo-slučajan broj od 0 do RAND_MAX. Za opseg 0..n-1: rand() % n. Pozovi srand(time(NULL)) jednom na početku."),
        f("srand", "void srand(unsigned seed)", "<stdlib.h>", "Postavlja početnu vrednost za rand. Obično: srand(time(NULL));"),
        f("atoi", "int atoi(const char *s)", "<stdlib.h>", "Pretvara string u ceo broj. Primer: atoi(\"42\") je 42."),
        f("atof", "double atof(const char *s)", "<stdlib.h>", "Pretvara string u realan broj."),
        f("qsort", "void qsort(void *niz, size_t n, size_t vel, int (*poredi)(const void*, const void*))", "<stdlib.h>",
          "Sortira niz od n elemenata pomoću tvoje funkcije poređenja (vraća <0, 0 ili >0)."),
        f("system", "int system(const char *komanda)", "<stdlib.h>", "Izvršava komandu operativnog sistema. Napomena: system(\"pause\") radi samo na Windows-u."),
        // <string.h>
        f("strlen", "size_t strlen(const char *s)", "<string.h>", "Vraća dužinu stringa (broj znakova pre '\\0')."),
        f("strcpy", "char *strcpy(char *odrediste, const char *izvor)", "<string.h>", "Kopira string izvor u odrediste. Pazi da odrediste bude dovoljno veliko."),
        f("strncpy", "char *strncpy(char *odr, const char *izv, size_t n)", "<string.h>", "Kopira najviše n znakova."),
        f("strcat", "char *strcat(char *odrediste, const char *izvor)", "<string.h>", "Nadovezuje izvor na kraj odredista."),
        f("strcmp", "int strcmp(const char *a, const char *b)", "<string.h>",
          "Poredi dva stringa: vraća 0 ako su isti, <0 ako je a pre b po abecedi, >0 ako je posle. Ne poredi stringove sa ==!"),
        f("strncmp", "int strncmp(const char *a, const char *b, size_t n)", "<string.h>", "Poredi prvih n znakova dva stringa."),
        f("strchr", "char *strchr(const char *s, int c)", "<string.h>", "Traži prvo pojavljivanje znaka c u s; vraća pokazivač ili NULL."),
        f("strstr", "char *strstr(const char *s, const char *trazi)", "<string.h>", "Traži podstring u stringu; vraća pokazivač ili NULL."),
        f("strtok", "char *strtok(char *s, const char *delimiteri)", "<string.h>", "Deli string na reči po delimiterima. Prvi poziv sa s, sledeći sa NULL."),
        f("memset", "void *memset(void *ptr, int vrednost, size_t n)", "<string.h>", "Postavlja n bajtova na vrednost. Primer: memset(niz, 0, sizeof(niz));"),
        f("memcpy", "void *memcpy(void *odr, const void *izv, size_t n)", "<string.h>", "Kopira n bajtova memorije."),
        // <ctype.h>
        f("toupper", "int toupper(int c)", "<ctype.h>", "Pretvara malo slovo u veliko ('a' → 'A')."),
        f("tolower", "int tolower(int c)", "<ctype.h>", "Pretvara veliko slovo u malo."),
        f("isdigit", "int isdigit(int c)", "<ctype.h>", "Da li je znak cifra '0'–'9'."),
        f("isalpha", "int isalpha(int c)", "<ctype.h>", "Da li je znak slovo."),
        f("isalnum", "int isalnum(int c)", "<ctype.h>", "Da li je znak slovo ili cifra."),
        f("isspace", "int isspace(int c)", "<ctype.h>", "Da li je znak razmak, tab ili novi red."),
        f("isupper", "int isupper(int c)", "<ctype.h>", "Da li je znak veliko slovo."),
        f("islower", "int islower(int c)", "<ctype.h>", "Da li je znak malo slovo."),
        // <math.h>
        f("sqrt", "double sqrt(double x)", "<math.h>", "Kvadratni koren. Primer: sqrt(16) je 4."),
        f("pow", "double pow(double osnova, double eksponent)", "<math.h>", "Stepenovanje. Primer: pow(2, 10) je 1024."),
        f("fabs", "double fabs(double x)", "<math.h>", "Apsolutna vrednost realnog broja."),
        f("sin", "double sin(double x)", "<math.h>", "Sinus ugla x u radijanima."),
        f("cos", "double cos(double x)", "<math.h>", "Kosinus ugla x u radijanima."),
        f("tan", "double tan(double x)", "<math.h>", "Tangens ugla x u radijanima."),
        f("floor", "double floor(double x)", "<math.h>", "Zaokružuje naniže (3.7 → 3)."),
        f("ceil", "double ceil(double x)", "<math.h>", "Zaokružuje naviše (3.2 → 4)."),
        f("round", "double round(double x)", "<math.h>", "Zaokružuje na najbliži ceo broj (2.5 → 3)."),
        f("log", "double log(double x)", "<math.h>", "Prirodni logaritam (ln x)."),
        f("log10", "double log10(double x)", "<math.h>", "Logaritam za osnovu 10."),
        f("exp", "double exp(double x)", "<math.h>", "e na x."),
        // <time.h>
        f("time", "time_t time(time_t *t)", "<time.h>", "Trenutno vreme u sekundama. Najčešće: srand(time(NULL));"),
        f("clock", "clock_t clock(void)", "<time.h>", "Procesorsko vreme od početka programa; podeli sa CLOCKS_PER_SEC za sekunde."),

        // C++ <iostream>
        o("cout", "std::ostream cout", "<iostream>", "Ispis na ekran. Primer: cout << \"Zbir je \" << a + b << endl;"),
        o("cin", "std::istream cin", "<iostream>", "Učitavanje sa tastature. Primer: cin >> a >> b; Čita do prvog razmaka — za celu liniju koristi getline."),
        o("cerr", "std::ostream cerr", "<iostream>", "Ispis poruka o greškama (odmah, bez baferovanja)."),
        o("endl", "std::endl", "<iostream>", "Novi red i pražnjenje bafera. Može i \"\\n\"."),
        f("getline", "istream& getline(istream& in, string& s)", "<string>",
          "Učitava celu liniju (sa razmacima) u string. Primer: getline(cin, ime); Ako je pre toga bilo cin >> x, prvo pozovi cin.ignore().", .cpp),
        o("string", "std::string", "<string>", "Tekst koji sam vodi računa o memoriji. s.size() dužina, s + t spajanje, s[i] i-ti znak, s == t poređenje.", .type),
        o("vector", "std::vector<T>", "<vector>", "Niz promenljive dužine. Primer: vector<int> v; v.push_back(5); v.size(); v[0].", .type),
        o("map", "std::map<K, V>", "<map>", "Rečnik ključ → vrednost, sortiran po ključu. Primer: map<string,int> m; m[\"ana\"] = 5;", .type),
        o("set", "std::set<T>", "<set>", "Skup različitih elemenata, sortiran.", .type),
        o("pair", "std::pair<A, B>", "<utility>", "Par dve vrednosti: p.first i p.second.", .type),
        f("make_pair", "pair<A,B> make_pair(A a, B b)", "<utility>", "Pravi par od dve vrednosti.", .cpp),
        f("sort", "void sort(Iterator pocetak, Iterator kraj)", "<algorithm>", "Sortira opseg rastuće. Primer: sort(v.begin(), v.end()); ili za niz: sort(a, a + n);", .cpp),
        f("reverse", "void reverse(Iterator pocetak, Iterator kraj)", "<algorithm>", "Obrće redosled elemenata u opsegu.", .cpp),
        f("swap", "void swap(T& a, T& b)", "<utility>", "Zamenjuje vrednosti dve promenljive.", .cpp),
        f("max", "const T& max(const T& a, const T& b)", "<algorithm>", "Veći od dva broja.", .cpp),
        f("min", "const T& min(const T& a, const T& b)", "<algorithm>", "Manji od dva broja.", .cpp),
        f("find", "Iterator find(Iterator pocetak, Iterator kraj, const T& vrednost)", "<algorithm>", "Traži vrednost u opsegu; vraća kraj ako je nema.", .cpp),
        f("to_string", "string to_string(int/double x)", "<string>", "Pretvara broj u string. Primer: to_string(42) je \"42\".", .cpp),
        f("stoi", "int stoi(const string& s)", "<string>", "Pretvara string u ceo broj.", .cpp),
        f("stod", "double stod(const string& s)", "<string>", "Pretvara string u realan broj.", .cpp),
        o("setw", "setw(int n)", "<iomanip>", "Sledeći ispis zauzima n mesta (poravnanje u kolonama). Primer: cout << setw(5) << x;", .function),
        o("setprecision", "setprecision(int n)", "<iomanip>", "Broj cifara pri ispisu realnih brojeva. Uz fixed: broj decimala. Primer: cout << fixed << setprecision(2) << x;", .function),
        o("fixed", "std::fixed", "<iomanip>", "Ispis realnih brojeva u fiksnom formatu (sa setprecision određuje broj decimala)."),
        o("ifstream", "std::ifstream", "<fstream>", "Čitanje iz fajla. Primer: ifstream ulaz(\"podaci.txt\"); ulaz >> x;", .type),
        o("ofstream", "std::ofstream", "<fstream>", "Pisanje u fajl. Primer: ofstream izlaz(\"rez.txt\"); izlaz << x;", .type),
    ]

    // MARK: Ključne reči i tipovi
    static let keywords: [DocItem] = [
        k("int", "Ceo broj (npr. -5, 0, 42). Obično 4 bajta, opseg oko ±2 milijarde.", kind: .type),
        k("double", "Realan broj dvostruke preciznosti (npr. 3.14). Za scanf koristi %lf.", kind: .type),
        k("float", "Realan broj manje preciznosti. Za veću tačnost koristi double.", kind: .type),
        k("char", "Jedan znak (npr. 'a'). U suštini mali ceo broj (ASCII kod).", kind: .type),
        k("long", "Duži ceo broj (long long za veoma velike brojeve).", kind: .type),
        k("short", "Kraći ceo broj.", kind: .type),
        k("unsigned", "Bez znaka — samo nenegativni brojevi, duplo veći gornji opseg.", kind: .type),
        k("void", "„Ništa“ — funkcija koja ne vraća vrednost, ili void* pokazivač na bilo šta.", kind: .type),
        k("bool", "Logička vrednost: true ili false. (U C-u: #include <stdbool.h>.)", kind: .type),
        k("if", "Uslov: if (uslov) { ... } else { ... }"),
        k("else", "Deo koji se izvršava kada uslov u if nije ispunjen."),
        k("for", "Petlja sa brojačem: for (int i = 0; i < n; i++) { ... }"),
        k("while", "Petlja dok važi uslov: while (uslov) { ... }"),
        k("do", "Petlja koja se izvrši bar jednom: do { ... } while (uslov);"),
        k("switch", "Izbor po vrednosti: switch (x) { case 1: ...; break; default: ...; }"),
        k("case", "Jedna grana u switch naredbi. Ne zaboravi break."),
        k("default", "Grana u switch-u kada nijedan case ne odgovara."),
        k("break", "Izlazi iz petlje ili switch-a."),
        k("continue", "Preskače ostatak tela petlje i ide na sledeći krug."),
        k("return", "Vraća vrednost iz funkcije i završava je. U main-u: return 0; znači uspešan kraj."),
        k("const", "Konstanta — vrednost se ne može menjati posle inicijalizacije."),
        k("static", "Promenljiva zadržava vrednost između poziva funkcije (ili je vidljiva samo u fajlu)."),
        k("struct", "Struktura — grupiše više polja: struct Student { char ime[30]; int ocena; };"),
        k("typedef", "Daje novo ime tipu: typedef struct Student Student;"),
        k("enum", "Nabrajanje imenovanih konstanti: enum Dan { PON, UTO, SRE };"),
        k("sizeof", "Veličina tipa ili promenljive u bajtovima: sizeof(int)."),
        k("goto", "Skok na labelu — izbegavaj, otežava čitanje koda."),
        k("NULL", "Prazan pokazivač (ne pokazuje ni na šta)."),
        k("true", "Logička vrednost tačno.", .cpp),
        k("false", "Logička vrednost netačno.", .cpp),
        k("class", "Klasa — kao struktura, ali sa metodama i private/public delovima.", .cpp),
        k("public", "Članovi klase dostupni svima.", .cpp),
        k("private", "Članovi klase dostupni samo unutar klase.", .cpp),
        k("protected", "Članovi dostupni klasi i njenim naslednicima.", .cpp),
        k("namespace", "Imenski prostor. using namespace std; omogućava cout umesto std::cout.", .cpp),
        k("using", "using namespace std; — koristi imena iz std bez prefiksa std::.", .cpp),
        k("new", "Dinamički pravi objekat ili niz: int *a = new int[n]; (oslobodi sa delete[]).", .cpp),
        k("delete", "Oslobađa memoriju dobijenu sa new (delete[] za nizove).", .cpp),
        k("nullptr", "Prazan pokazivač u C++ (bolje od NULL).", .cpp),
        k("auto", "Kompajler sam određuje tip: auto x = 5; (u C++).", .cpp),
        k("template", "Šablon — funkcija ili klasa za više tipova: template <typename T>.", .cpp),
        k("this", "Pokazivač na trenutni objekat unutar metode klase.", .cpp),
        k("virtual", "Metoda koju naslednik može da preradi (polimorfizam).", .cpp),
        k("try", "Blok u kome se hvataju izuzeci: try { ... } catch (...) { ... }", .cpp),
        k("catch", "Hvata izuzetak bačen u try bloku.", .cpp),
        k("throw", "Baca izuzetak.", .cpp),
    ]

    // MARK: Metode posle tačke (string, vector, map)
    static let members: [DocItem] = [
        m("size", "size_t size()", "string / vector / map", "Broj elemenata (za string: broj znakova)."),
        m("length", "size_t length()", "string", "Dužina stringa (isto što i size())."),
        m("empty", "bool empty()", "string / vector / map", "Da li je prazno."),
        m("clear", "void clear()", "string / vector / map", "Briše sve elemente."),
        m("push_back", "void push_back(const T& x)", "vector / string", "Dodaje element na kraj."),
        m("pop_back", "void pop_back()", "vector / string", "Uklanja poslednji element."),
        m("emplace_back", "void emplace_back(args...)", "vector", "Pravi element direktno na kraju (brže od push_back za objekte)."),
        m("at", "T& at(size_t i)", "string / vector", "Element na poziciji i, sa proverom granica (baca izuzetak ako je i van opsega)."),
        m("front", "T& front()", "string / vector", "Prvi element."),
        m("back", "T& back()", "string / vector", "Poslednji element."),
        m("begin", "iterator begin()", "string / vector / map", "Iterator na početak — za sort(v.begin(), v.end())."),
        m("end", "iterator end()", "string / vector / map", "Iterator iza poslednjeg elementa."),
        m("insert", "insert(pozicija, vrednost)", "string / vector / map", "Ubacuje element na poziciju."),
        m("erase", "erase(pozicija)", "string / vector / map", "Briše element na poziciji (ili opseg)."),
        m("resize", "void resize(size_t n)", "vector / string", "Menja broj elemenata na n."),
        m("substr", "string substr(size_t pos, size_t duzina)", "string", "Deo stringa od pozicije pos, zadate dužine. Primer: s.substr(0, 3)."),
        m("find", "size_t find(const string& t)", "string / map", "Pozicija prvog pojavljivanja (string::npos ako ga nema). Za map: iterator na ključ."),
        m("c_str", "const char* c_str()", "string", "C-string verzija (za funkcije kao printf(\"%s\", s.c_str()))."),
        m("append", "string& append(const string& t)", "string", "Dodaje t na kraj (isto kao s += t)."),
        m("compare", "int compare(const string& t)", "string", "Poredi stringove: 0 ako su jednaki."),
        m("count", "size_t count(const K& kljuc)", "map / set", "1 ako ključ postoji, inače 0."),
        m("first", "first", "pair", "Prvi element para."),
        m("second", "second", "pair", "Drugi element para."),
        m("ignore", "istream& ignore()", "cin", "Preskače znak(ove) u ulazu — pre getline posle cin >>."),
        m("open", "void open(const char* ime)", "ifstream / ofstream", "Otvara fajl."),
        m("close", "void close()", "ifstream / ofstream", "Zatvara fajl."),
        m("is_open", "bool is_open()", "ifstream / ofstream", "Da li je fajl uspešno otvoren."),
        m("eof", "bool eof()", "ifstream / cin", "Da li je dostignut kraj ulaza."),
    ]

    // MARK: Pretprocesor i biblioteke
    static let directives: [DocItem] = [
        DocItem(name: "include", signature: "#include <biblioteka>", header: "pretprocesor", summary: "Uključuje biblioteku ili tvoj header fajl (\"moj.h\").", kind: .directive, lang: .c),
        DocItem(name: "define", signature: "#define IME vrednost", header: "pretprocesor", summary: "Konstanta ili makro. Primer: #define MAX 100", kind: .directive, lang: .c),
        DocItem(name: "ifndef", signature: "#ifndef IME", header: "pretprocesor", summary: "Uslovno uključivanje (header guard).", kind: .directive, lang: .c),
        DocItem(name: "endif", signature: "#endif", header: "pretprocesor", summary: "Kraj #if/#ifdef/#ifndef bloka.", kind: .directive, lang: .c),
        DocItem(name: "pragma", signature: "#pragma once", header: "pretprocesor", summary: "Header se uključuje samo jednom.", kind: .directive, lang: .c),
    ]

    static let headers: [DocItem] = {
        let list: [(String, String, DocLang)] = [
            ("stdio.h", "Ulaz/izlaz: printf, scanf, fopen, fgets…", .c),
            ("stdlib.h", "malloc, free, rand, atoi, exit, qsort…", .c),
            ("string.h", "Rad sa C stringovima: strlen, strcpy, strcmp…", .c),
            ("math.h", "Matematika: sqrt, pow, sin, cos, fabs…", .c),
            ("ctype.h", "Znakovi: isdigit, isalpha, toupper…", .c),
            ("time.h", "Vreme: time, clock", .c),
            ("stdbool.h", "Tip bool u C-u (true/false)", .c),
            ("limits.h", "INT_MAX, INT_MIN…", .c),
            ("iostream", "cout, cin, endl", .cpp),
            ("string", "std::string, getline, to_string", .cpp),
            ("vector", "std::vector", .cpp),
            ("algorithm", "sort, reverse, min, max, find", .cpp),
            ("cmath", "Matematika u C++: sqrt, pow…", .cpp),
            ("iomanip", "setw, setprecision, fixed", .cpp),
            ("fstream", "Fajlovi: ifstream, ofstream", .cpp),
            ("map", "std::map", .cpp),
            ("set", "std::set", .cpp),
            ("cstdlib", "rand, srand, abs… u C++", .cpp),
            ("cstring", "strlen, strcpy… u C++", .cpp),
            ("ctime", "time u C++", .cpp),
        ]
        return list.map { DocItem(name: $0.0, signature: "#include <\($0.0)>", header: "biblioteka", summary: $0.1, kind: .header, lang: $0.2) }
    }()

    static let byName: [String: DocItem] = {
        var d: [String: DocItem] = [:]
        for it in keywords { d[it.name] = it }
        for it in library { d[it.name] = it }
        return d
    }()

    static func base(isC: Bool) -> [DocItem] {
        (library + keywords).filter { !isC || $0.lang == .c }
    }

    // MARK: Tvoje funkcije, promenljive, strukture i makroi

    private static let varRe = try! NSRegularExpression(
        pattern: #"(?:^|[;{(,]\s*|\n\s*)((?:const\s+|unsigned\s+|signed\s+|static\s+|long\s+)*(?:int|double|float|char|bool|long|short|size_t|string|auto|FILE|struct\s+\w+|vector\s*<[^;>]*>|map\s*<[^;>]*>)\s*\**\s*)([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*(?=[=;,)\[])"#,
        options: [.anchorsMatchLines])
    private static let defineRe = try! NSRegularExpression(pattern: #"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)(.*)$"#, options: [.anchorsMatchLines])
    private static let structRe = try! NSRegularExpression(pattern: #"\b(struct|class)\s+([A-Za-z_]\w*)\s*\{([^{}]*)\}"#)
    private static let fieldRe = try! NSRegularExpression(pattern: #"([A-Za-z_][\w\s\*<>,:]*?)\s+\**([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*;"#)

    static func lineNumber(_ ns: NSString, _ loc: Int) -> Int {
        var line = 1
        var i = 0
        while i < loc {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: i, length: loc - i))
            if r.location == NSNotFound { break }
            line += 1
            i = r.location + 1
        }
        return line
    }

    /// Komentar neposredno iznad linije (// ... ili /* ... */)
    private static func commentAbove(_ lines: [String], _ lineIdx: Int) -> String? {
        var i = lineIdx - 1
        var collected: [String] = []
        while i >= 0 {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("//") {
                collected.insert(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces), at: 0)
                i -= 1
            } else if t.hasSuffix("*/") {
                var block: [String] = []
                while i >= 0 {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    block.insert(l.replacingOccurrences(of: "/*", with: "").replacingOccurrences(of: "*/", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " *")), at: 0)
                    if l.hasPrefix("/*") { break }
                    i -= 1
                }
                collected.insert(contentsOf: block, at: 0)
                break
            } else {
                break
            }
        }
        let s = collected.filter { !$0.isEmpty }.joined(separator: " ")
        return s.isEmpty ? nil : s
    }

    static func userItems(_ files: [(name: String, text: String)]) -> (items: [DocItem], fields: [DocItem]) {
        var items: [DocItem] = []
        var fields: [DocItem] = []
        var seen = Set<String>()
        for (fname, text) in files {
            let ns = text as NSString
            let lines = text.components(separatedBy: "\n")
            let full = NSRange(location: 0, length: ns.length)
            for s in Workspace.symbols(in: text) where !seen.contains("f:" + s.name) {
                seen.insert("f:" + s.name)
                let comment = commentAbove(lines, s.line - 1)
                items.append(DocItem(name: s.name, signature: s.signature, header: "\(fname), linija \(s.line)",
                                     summary: comment ?? "Tvoja funkcija.", kind: .userFunction, lang: .c))
            }
            for mt in defineRe.matches(in: text, range: full) {
                let name = ns.substring(with: mt.range(at: 1))
                guard !seen.contains("d:" + name) else { continue }
                seen.insert("d:" + name)
                let val = ns.substring(with: mt.range(at: 2)).trimmingCharacters(in: .whitespaces)
                items.append(DocItem(name: name, signature: "#define \(name) \(val)", header: "\(fname), linija \(lineNumber(ns, mt.range.location))",
                                     summary: "Tvoja konstanta (makro).", kind: .macro, lang: .c))
            }
            for mt in structRe.matches(in: text, range: full) {
                let kw = ns.substring(with: mt.range(at: 1))
                let name = ns.substring(with: mt.range(at: 2))
                if !seen.contains("s:" + name) {
                    seen.insert("s:" + name)
                    items.append(DocItem(name: name, signature: "\(kw) \(name)", header: "\(fname), linija \(lineNumber(ns, mt.range.location))",
                                         summary: "Tvoja struktura.", kind: .type, lang: .c))
                }
                let body = ns.substring(with: mt.range(at: 3))
                let bns = body as NSString
                for fm in fieldRe.matches(in: body, range: NSRange(location: 0, length: bns.length)) {
                    let type = bns.substring(with: fm.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let fieldName = bns.substring(with: fm.range(at: 2))
                    let arr = fm.range(at: 3).location != NSNotFound ? bns.substring(with: fm.range(at: 3)) : ""
                    if ["return", "public", "private"].contains(type) { continue }
                    fields.append(DocItem(name: fieldName, signature: "\(type) \(fieldName)\(arr)", header: "polje u \(kw) \(name)",
                                          summary: "Polje tvoje strukture \(name).", kind: .field, lang: .c))
                }
            }
            for mt in varRe.matches(in: text, range: full) {
                let name = ns.substring(with: mt.range(at: 2))
                if byName[name]?.kind == .keyword || byName[name]?.kind == .type { continue }
                guard !seen.contains("v:" + name) && !seen.contains("f:" + name) else { continue }
                seen.insert("v:" + name)
                let type = ns.substring(with: mt.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let arr = mt.range(at: 3).location != NSNotFound ? ns.substring(with: mt.range(at: 3)) : ""
                items.append(DocItem(name: name, signature: "\(type) \(name)\(arr)", header: "\(fname), linija \(lineNumber(ns, mt.range(at: 2).location))",
                                     summary: "Tvoja promenljiva.", kind: .variable, lang: .c))
            }
        }
        return (items, fields)
    }

    /// Rangira predloge: prvo tačan početak (velika/mala slova), pa početak bez obzira na slova, pa sadrži.
    static func rank(_ all: [DocItem], prefix: String, limit: Int = 60) -> [DocItem] {
        if prefix.isEmpty {
            return Array(dedupe(all).sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(limit))
        }
        let p = prefix.lowercased()
        var a: [DocItem] = [], b: [DocItem] = [], c: [DocItem] = []
        for it in all {
            if it.name.hasPrefix(prefix) { a.append(it) }
            else if it.name.lowercased().hasPrefix(p) { b.append(it) }
            else if prefix.count >= 2 && it.name.lowercased().contains(p) { c.append(it) }
        }
        let sort: (DocItem, DocItem) -> Bool = { x, y in
            if x.name.count != y.name.count && (x.name.lowercased().hasPrefix(p) && y.name.lowercased().hasPrefix(p)) {
                return x.name.lowercased() < y.name.lowercased()
            }
            return x.name.lowercased() < y.name.lowercased()
        }
        return Array(dedupe(a.sorted(by: sort) + b.sorted(by: sort) + c.sorted(by: sort)).prefix(limit))
    }

    private static func dedupe(_ items: [DocItem]) -> [DocItem] {
        var seen = Set<String>()
        var out: [DocItem] = []
        for it in items where !seen.contains(it.name) {
            seen.insert(it.name)
            out.append(it)
        }
        return out
    }
}
