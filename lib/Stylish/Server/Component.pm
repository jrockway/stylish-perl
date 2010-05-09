use MooseX::Declare;

role Stylish::Server::Component {
    requires 'SERVER';
    requires 'UNSERVER';
    requires 'SESSION';
    requires 'UNSESSION';
}
