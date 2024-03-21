import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import Option "mo:base/Option";

module Http {
    public type Request = {
        body : Blob;
        headers : [HeaderField];
        method : Text;
        url : Text;
    };

    public type HeaderField = (Text, Text);

    public type Response = {
        body : Blob;
        headers : [HeaderField];
        status_code : Nat16;
    };

    public func BAD_REQUEST() : Response = error(400);
    public func UNAUTHORIZED() : Response = error(401);
    public func NOT_FOUND() : Response = error(404);

    private func error(statusCode : Nat16) : Response = {
        status_code = statusCode;
        headers = [];
        body = Blob.fromArray([]);
    };
};
