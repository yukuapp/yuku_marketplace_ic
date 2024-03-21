import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Time "mo:base/Time";
import P "mo:base/Prelude";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Prim "mo:⛔";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import AviatePrincipal "mo:principal/Principal";
import Binary "mo:encoding/Binary";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Ext "mo:ext/Ext";

module {

    public func filter<T>(xs : [var T], t : T, f : (T, T) -> Bool) : [var T] {
        let ys : Buffer.Buffer<T> = Buffer.Buffer(xs.size());
        label l for (x in xs.vals()) {
            if (f(x, t)) {
                continue l;
            };
            ys.add(x);
        };
        return ys.toVarArray();
    };

    public func exist<T>(xs : [var T], f : T -> Bool) : Bool {
        for (x in xs.vals()) {
            if (f(x)) {
                return true;
            };
        };
        return false;
    };

    public func existIm<T>(xs : [T], f : T -> Bool) : Bool {
        for (x in xs.vals()) {
            if (f(x)) {
                return true;
            };
        };
        return false;
    };

    public func isLeapYear(year : Nat) : Bool {
        return ((year % 4 == 0 and year % 100 != 0) or (year % 400 == 0));
    };

    public func getDaysForYear(year : Nat) : Nat {
        if (isLeapYear(year)) 366 else 365;
    };

    //获取当前时间，返回字符串，格式： yyyy-mm-dd hh:mm:ss
    public func parseTime(time : Int) : Text {
        var mon_yday = [[0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365], [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366]];
        var seconds = time / 1000000000;
        var min = seconds / 60;
        var hour = min / 60;
        var day = hour / 24;
        var curYear = 1970;
        var month = 0;

        //计算年
        var daysCurYear = getDaysForYear(curYear);
        while (day >= daysCurYear) {
            day -= daysCurYear;
            curYear += 1;
            daysCurYear := getDaysForYear(curYear);
        };
        //计算月日
        var key = 0;
        if (isLeapYear(curYear)) key := 1;
        var i = 1;
        while (i < 13) {
            if (day < mon_yday[key][i]) {
                month := i;
                day := day - mon_yday[key][i -1] + 1;
                i := 13;
            };
            i += 1;
        };
        seconds %= 60;
        min %= 60;
        hour %= 24;
        return Int.toText(curYear) # "-" #Int.toText(month) # "-" #Int.toText(day) # " " #Int.toText(hour) # ":" #Int.toText(min) # ":" #Int.toText(seconds);
    };

    public func getTtlByMinute(minutes : Nat) : Int {
        Time.now() + minutes * 60 * 1000000000;
    };

    public func getTtlByDay(day : Nat) : Int {
        Time.now() + day * 24 * 60 * 60 * 1000000000;
    };

    public func unwrap<T>(x : ?T) : T = switch x {
        case null { P.unreachable() };
        case (?x_) { x_ };
    };

    public func textToNat(str : Text) : Nat {
        let chars : [Char] = Iter.toArray(Text.toIter(str));
        var index : Nat = chars.size() - 1;
        var result : Nat = 0;
        for (char in chars.vals()) {
            if (Char.isDigit(char)) {
                let nat_char = Char.toNat32(char);
                let nat32 = nat_char - 48;
                let nat : Nat = Nat32.toNat(nat32);
                result := result + nat * Nat.pow(10, index);
                if (index != 0) {
                    index -= 1;
                };
            };
        };
        result;
    };

    public func copy<A>(xs : [A], start : Nat, length : Nat) : [A] {
        if (start > xs.size()) return [];

        let size : Nat = xs.size() - start;
        var items = length;

        if (size < length) items := size;

        Prim.Array_tabulate<A>(
            items,
            func(i : Nat) : A {
                xs[i +start];
            },
        );
    };

    public func reverse<A>(xs : [A]) : [A] {
        let size = xs.size();
        Prim.Array_tabulate<A>(
            size,
            func(i : Nat) : A {
                xs[size - 1 - i];
            },
        );
    };

    public type TokenIndex = Nat32;
    private let prefix : [Nat8] = [10, 116, 105, 100]; // \x0A "tid"
    public func encode(canisterId : Principal, tokenIndex : TokenIndex) : Text {
        let rawTokenId = Array.flatten<Nat8>([
            prefix,
            Blob.toArray(AviatePrincipal.toBlob(canisterId)),
            Binary.BigEndian.fromNat32(tokenIndex),
        ]);

        AviatePrincipal.toText(AviatePrincipal.fromBlob(Blob.fromArray(rawTokenId)));
    };

    // principal to subAccount
    public func principalToSubAccount(id : Principal) : [Nat8] {
        let p = Blob.toArray(Principal.toBlob(id));
        Array.tabulate(
            32,
            func(i : Nat) : Nat8 {
                if (i >= p.size() + 1) 0 else if (i == 0) (Nat8.fromNat(p.size())) else (p[i - 1]);
            },
        );
    };

    //quicksort
    func qSort(arr : [(TokenIndex, Float)]) : [(TokenIndex, Float)] {
        var newArr : [var (TokenIndex, Float)] = Array.thaw(arr);
        sort(newArr, 0, newArr.size() -1);
        Array.freeze(newArr);
    };

    func sort(arr : [var (TokenIndex, Float)], low : Nat, high : Nat) {
        if (low >= high) return;
        var temp = arr[low];
        var left = low;
        var right = high;
        while (left < right) {
            while (arr[right].1 <= temp.1 and right > left) {
                right -= 1;
            };
            arr[left] := arr[right];
            while (arr[left].1 >= temp.1 and left < right) {
                left += 1;
            };
            arr[right] := arr[left];
        };
        arr[right] := temp;
        if (left >= 1) sort(arr, low, left -1);
        sort(arr, left +1, high);
    };

    public func quickSort(arr : [(TokenIndex, Float)]) : [(TokenIndex, Float)] {
        qSort(arr);
    };
};
