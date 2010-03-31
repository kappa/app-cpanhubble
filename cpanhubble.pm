package cpanhubble;
use Dancer;

get '/' => sub {
    template 'index';
};

true;
